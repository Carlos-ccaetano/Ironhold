defmodule Ironhold.Webhooks do
  @moduledoc """
  Stores webhook envelopes received by Ironhold.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Ironhold.Repo
  alias Ironhold.Webhooks.{ReceivedWebhook, WebhookReplayClaim}
  alias IronholdWeb.Telemetry

  @event_id_constraint "received_webhooks_event_id_index"
  @fingerprint_constraint "webhook_replay_claims_fingerprint_index"

  def receive_webhook(attrs, received_at \\ DateTime.utc_now()) when is_map(attrs) do
    %ReceivedWebhook{}
    |> ReceivedWebhook.changeset(put_received_at(attrs, received_at))
    |> Repo.insert()
    |> normalize_insert_result()
  end

  def ingest_authenticated_webhook(attrs, fingerprint, expires_at) when is_map(attrs) do
    replay_claim_changeset =
      WebhookReplayClaim.changeset(%WebhookReplayClaim{}, %{
        fingerprint: fingerprint,
        expires_at: expires_at
      })

    webhook_changeset =
      ReceivedWebhook.changeset(%ReceivedWebhook{}, put_received_at(attrs, DateTime.utc_now()))

    Multi.new()
    |> Multi.insert(:replay_claim, replay_claim_changeset)
    |> Multi.run(:webhook, fn repo, _changes ->
      insert_or_acknowledge_webhook(repo, webhook_changeset)
    end)
    |> Repo.transaction()
    |> normalize_ingestion_result()
  end

  defp insert_or_acknowledge_webhook(repo, changeset) do
    case repo.insert(changeset, on_conflict: :nothing, conflict_target: [:event_id]) do
      {:ok, %ReceivedWebhook{id: nil} = webhook} -> acknowledge_existing_webhook(repo, webhook)
      result -> result
    end
  end

  defp acknowledge_existing_webhook(repo, webhook) do
    persisted_webhook =
      repo.one(
        from persisted in ReceivedWebhook,
          where: persisted.event_id == ^webhook.event_id,
          lock: "FOR UPDATE"
      )

    case persisted_webhook do
      %ReceivedWebhook{} = persisted -> compare_webhook_envelope(persisted, webhook)
      nil -> {:error, :invalid_webhook}
    end
  end

  defp compare_webhook_envelope(persisted, candidate) do
    if persisted.event_type == candidate.event_type and persisted.payload == candidate.payload do
      {:ok, persisted}
    else
      {:error, :duplicate_event}
    end
  end

  def prune_expired_replay_claims(reference_time) do
    {deleted_count, _} =
      Repo.delete_all(
        from claim in WebhookReplayClaim,
          where: claim.expires_at <= ^reference_time
      )

    deleted_count
  end

  defp put_received_at(attrs, received_at) do
    key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "received_at", else: :received_at
    Map.put(attrs, key, received_at)
  end

  defp normalize_insert_result({:error, %Ecto.Changeset{} = changeset} = result) do
    if duplicate_event_id?(changeset), do: {:error, :duplicate_event_id}, else: result
  end

  defp normalize_insert_result(result), do: result

  defp normalize_ingestion_result({:ok, %{webhook: webhook}}) do
    Telemetry.emit_replay_claim_accepted()
    {:ok, webhook}
  end

  defp normalize_ingestion_result(
         {:error, :replay_claim, %Ecto.Changeset{} = changeset, _changes}
       ) do
    if constraint_error?(changeset, :fingerprint, :unique, @fingerprint_constraint) do
      Telemetry.emit_replay_detected()
      {:error, :replay_detected}
    else
      {:error, :invalid_replay_claim}
    end
  end

  defp normalize_ingestion_result({:error, :webhook, :duplicate_event, _changes}) do
    {:error, :duplicate_event}
  end

  defp normalize_ingestion_result({:error, :webhook, %Ecto.Changeset{} = changeset, _changes}) do
    if constraint_error?(changeset, :event_id, :unique, @event_id_constraint) do
      {:error, :duplicate_event}
    else
      {:error, :invalid_webhook}
    end
  end

  defp duplicate_event_id?(changeset) do
    constraint_error?(changeset, :event_id, :unique, @event_id_constraint)
  end

  defp constraint_error?(changeset, field, type, name) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.any?(fn {_message, metadata} ->
      metadata[:constraint] == type and metadata[:constraint_name] == name
    end)
  end
end
