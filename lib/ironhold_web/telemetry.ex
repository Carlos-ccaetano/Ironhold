defmodule IronholdWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  @accepted_event [:ironhold, :webhooks, :ingestion, :accepted]
  @idempotent_retry_event [:ironhold, :webhooks, :ingestion, :idempotent_retry]
  @rejected_event [:ironhold, :webhooks, :ingestion, :rejected]
  @replay_claim_accepted_event [:ironhold, :webhooks, :replay, :claim_accepted]
  @replay_detected_event [:ironhold, :webhooks, :replay, :detected]
  @replay_cleanup_completed_event [:ironhold, :webhooks, :replay, :cleanup_completed]
  @authentication_verified_event [:ironhold, :webhooks, :authentication, :verified]
  @authentication_rejected_event [:ironhold, :webhooks, :authentication, :rejected]
  @identifier_mismatch_event [:ironhold, :webhooks, :authentication, :identifier_mismatch]
  @cleanup_origins [:manual, :scheduled]
  @rejection_reasons [:validation, :replay_detected, :duplicate_event, :unsupported_media_type]

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: [], period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def emit_ingestion_accepted do
    :telemetry.execute(@accepted_event, %{count: 1}, %{})
  end

  def emit_idempotent_retry do
    :telemetry.execute(@idempotent_retry_event, %{count: 1}, %{})
  end

  def emit_ingestion_rejected(reason) when reason in @rejection_reasons do
    :telemetry.execute(@rejected_event, %{count: 1}, %{reason: reason})
  end

  def emit_replay_claim_accepted do
    :telemetry.execute(@replay_claim_accepted_event, %{count: 1}, %{})
  end

  def emit_replay_detected do
    :telemetry.execute(@replay_detected_event, %{count: 1}, %{})
  end

  def emit_replay_cleanup_completed({:ok, claims_removed}, duration, origin)
      when is_integer(claims_removed) and claims_removed >= 0 and is_integer(duration) and
             duration >= 0 and origin in @cleanup_origins do
    :telemetry.execute(
      @replay_cleanup_completed_event,
      %{count: 1, claims_removed: claims_removed, duration: duration},
      %{result: :ok, origin: origin}
    )
  end

  def emit_replay_cleanup_completed({:error, :cleanup_failed}, duration, origin)
      when is_integer(duration) and duration >= 0 and origin in @cleanup_origins do
    :telemetry.execute(
      @replay_cleanup_completed_event,
      %{count: 1, duration: duration},
      %{result: :error, origin: origin}
    )
  end

  def emit_authentication_verified do
    :telemetry.execute(@authentication_verified_event, %{count: 1}, %{})
  end

  def emit_authentication_rejected do
    :telemetry.execute(@authentication_rejected_event, %{count: 1}, %{})
  end

  def emit_authentication_identifier_mismatch do
    :telemetry.execute(@identifier_mismatch_event, %{count: 1}, %{})
  end

  def metrics do
    [
      counter("ironhold.webhooks.ingestion.accepted.count"),
      counter("ironhold.webhooks.ingestion.idempotent_retry.count"),
      counter("ironhold.webhooks.ingestion.rejected.count", tags: [:reason]),
      counter("ironhold.webhooks.replay.claim_accepted.count"),
      counter("ironhold.webhooks.replay.detected.count"),
      counter("ironhold.webhooks.replay.cleanup_completed.count", tags: [:result, :origin]),
      sum("ironhold.webhooks.replay.cleanup_completed.claims_removed",
        tags: [:result, :origin],
        keep: &match?(%{result: :ok}, &1)
      ),
      summary("ironhold.webhooks.replay.cleanup_completed.duration",
        tags: [:result, :origin],
        unit: {:native, :millisecond}
      ),
      counter("ironhold.webhooks.authentication.verified.count"),
      counter("ironhold.webhooks.authentication.rejected.count"),
      counter("ironhold.webhooks.authentication.identifier_mismatch.count"),
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("ironhold.repo.query.total_time", unit: {:native, :millisecond}),
      summary("ironhold.repo.query.queue_time", unit: {:native, :millisecond})
    ]
  end
end
