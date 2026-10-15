defmodule IronholdWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias IronholdWeb.Telemetry, as: IronholdTelemetry
  alias Telemetry.Metrics.{Counter, Sum, Summary}

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

    assert %Counter{
             event_name: [:ironhold, :webhooks, :ingestion, :idempotent_retry],
             measurement: :count,
             tags: []
           } = metric(metrics, [:ironhold, :webhooks, :ingestion, :idempotent_retry, :count])
  end

  test "declares untagged authentication counters" do
    metrics = IronholdTelemetry.metrics()

    for event <- [:verified, :rejected, :identifier_mismatch] do
      assert %Counter{
               event_name: [:ironhold, :webhooks, :authentication, ^event],
               measurement: :count,
               tags: []
             } = metric(metrics, [:ironhold, :webhooks, :authentication, event, :count])
    end
  end

  test "declares low-cardinality replay protection metrics" do
    metrics = IronholdTelemetry.metrics()

    assert %Counter{
             event_name: [:ironhold, :webhooks, :replay, :claim_accepted],
             measurement: :count,
             tags: []
           } = metric(metrics, [:ironhold, :webhooks, :replay, :claim_accepted, :count])

    assert %Counter{
             event_name: [:ironhold, :webhooks, :replay, :detected],
             measurement: :count,
             tags: []
           } = metric(metrics, [:ironhold, :webhooks, :replay, :detected, :count])

    assert %Counter{
             event_name: [:ironhold, :webhooks, :replay, :cleanup_completed],
             measurement: :count,
             tags: [:result, :origin]
           } =
             metric(metrics, [
               :ironhold,
               :webhooks,
               :replay,
               :cleanup_completed,
               :count
             ])

    claims_removed_metric =
      metric(metrics, [
        :ironhold,
        :webhooks,
        :replay,
        :cleanup_completed,
        :claims_removed
      ])

    assert %Sum{
             event_name: [:ironhold, :webhooks, :replay, :cleanup_completed],
             measurement: :claims_removed,
             tags: [:result, :origin]
           } = claims_removed_metric

    assert claims_removed_metric.keep.(%{result: :ok})
    refute claims_removed_metric.keep.(%{result: :error})

    duration_metric =
      metric(metrics, [
        :ironhold,
        :webhooks,
        :replay,
        :cleanup_completed,
        :duration
      ])

    assert %Summary{
             event_name: [:ironhold, :webhooks, :replay, :cleanup_completed],
             tags: [:result, :origin],
             unit: :millisecond
           } = duration_metric

    assert is_function(duration_metric.measurement, 1)
  end

  defp metric(metrics, name), do: Enum.find(metrics, &(&1.name == name))
end
