defmodule Ironhold.Webhooks do
  @moduledoc """
  Stores webhook envelopes received by Ironhold.
  """

  alias Ironhold.Repo
  alias Ironhold.Webhooks.ReceivedWebhook

  def receive_webhook(attrs, received_at \\ DateTime.utc_now()) when is_map(attrs) do
    %ReceivedWebhook{}
    |> ReceivedWebhook.changeset(put_received_at(attrs, received_at))
    |> Repo.insert()
    |> normalize_insert_result()
  end

  defp put_received_at(attrs, received_at) do
    key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "received_at", else: :received_at
    Map.put(attrs, key, received_at)
  end

  defp normalize_insert_result({:error, %Ecto.Changeset{} = changeset} = result) do
    if duplicate_event_id?(changeset), do: {:error, :duplicate_event_id}, else: result
  end

  defp normalize_insert_result(result), do: result

  defp duplicate_event_id?(changeset) do
    changeset.errors
    |> Keyword.get_values(:event_id)
    |> Enum.any?(fn {_message, metadata} -> metadata[:constraint] == :unique end)
  end
end
