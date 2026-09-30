defmodule IronholdWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias IronholdWeb.Telemetry, as: IronholdTelemetry
  alias Telemetry.Metrics.Counter

  test "declares ingestion counters for the emitted events" do
    metrics = IronholdTelemetry.metrics()

    assert %Counter{
             event_name: [:ironhold, :webhooks, :ingestion, :accepted],
             measurement: :count,
             tags: []
           } = metric(metrics, [:ironhold, :webhooks, :ingestion, :accepted, :count])

    assert %Counter{
             event_name: [:ironhold, :webhooks, :ingestion, :rejected],
             measurement: :count,
             tags: [:reason]
           } = metric(metrics, [:ironhold, :webhooks, :ingestion, :rejected, :count])
  end

  defp metric(metrics, name), do: Enum.find(metrics, &(&1.name == name))
end
