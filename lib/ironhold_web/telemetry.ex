defmodule IronholdWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  @accepted_event [:ironhold, :webhooks, :ingestion, :accepted]
  @rejected_event [:ironhold, :webhooks, :ingestion, :rejected]
  @rejection_reasons [:validation, :duplicate_event_id, :unsupported_media_type]

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

  def emit_ingestion_rejected(reason) when reason in @rejection_reasons do
    :telemetry.execute(@rejected_event, %{count: 1}, %{reason: reason})
  end

  def metrics do
    [
      counter("ironhold.webhooks.ingestion.accepted.count"),
      counter("ironhold.webhooks.ingestion.rejected.count", tags: [:reason]),
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
