defmodule Ironhold.Webhooks.ReplayCleanupTest do
  use Ironhold.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ironhold.Webhooks.{ReplayCleanup, WebhookReplayClaim}

  @cleanup_completed_event [:ironhold, :webhooks, :replay, :cleanup_completed]
  @reference_time ~U[2026-10-15 12:00:00.000000Z]
  @sensitive_keys [
    :signature,
    :fingerprint,
    :secret,
    :event_id,
    :url,
    :payload,
    :headers,
    :ip,
    :body,
    :stacktrace,
    :stack_trace
  ]

  test "starts under the application supervisor" do
    assert {ReplayCleanup, pid, :worker, _modules} =
             Enum.find(Supervisor.which_children(Ironhold.Supervisor), fn
               {ReplayCleanup, _pid, :worker, _modules} -> true
               _child -> false
             end)

    assert Process.alive?(pid)
  end

  test "removes expired claims, preserves valid claims, and remains functional" do
    attach_cleanup_event()
    cleanup = start_cleanup()
    expired_fingerprint = String.duplicate("a", 64)
    other_expired_fingerprint = String.duplicate("b", 64)
    future_fingerprint = String.duplicate("c", 64)

    insert_claim(expired_fingerprint, DateTime.add(@reference_time, -1, :second))
    insert_claim(other_expired_fingerprint, @reference_time)
    insert_claim(future_fingerprint, DateTime.add(@reference_time, 1, :second))

    assert ReplayCleanup.run_now(@reference_time, cleanup) == {:ok, 2}

    assert_receive {:cleanup_event,
                    %{count: 1, claims_removed: 2, duration: duration} = measurements,
                    %{result: :ok, origin: :manual} = metadata}

    assert duration >= 0
    assert Map.keys(measurements) |> Enum.sort() == [:claims_removed, :count, :duration]
    assert Map.keys(metadata) |> Enum.sort() == [:origin, :result]
    refute_sensitive_keys(measurements)
    refute_sensitive_keys(metadata)
    assert Repo.aggregate(WebhookReplayClaim, :count) == 1
    assert Repo.get_by(WebhookReplayClaim, fingerprint: future_fingerprint)

    later_fingerprint = String.duplicate("d", 64)
    insert_claim(later_fingerprint, @reference_time)

    assert ReplayCleanup.run_now(@reference_time, cleanup) == {:ok, 1}
    assert_receive {:cleanup_event, %{count: 1, claims_removed: 1}, %{result: :ok}}
    assert Process.alive?(cleanup)
    assert Repo.aggregate(WebhookReplayClaim, :count) == 1
  end

  test "continues after a cleanup failure" do
    attach_cleanup_event()
    cleanup = start_cleanup()
    fingerprint = String.duplicate("e", 64)

    assert ReplayCleanup.run_now(:invalid_reference_time, cleanup) ==
             {:error, :cleanup_failed}

    assert_receive {:cleanup_event, %{count: 1, duration: duration} = measurements,
                    %{result: :error, origin: :manual} = metadata}

    assert duration >= 0
    assert Map.keys(measurements) |> Enum.sort() == [:count, :duration]
    assert Map.keys(metadata) |> Enum.sort() == [:origin, :result]
    refute Map.has_key?(measurements, :claims_removed)
    refute_sensitive_keys(measurements)
    refute_sensitive_keys(metadata)

    insert_claim(fingerprint, @reference_time)

    assert ReplayCleanup.run_now(@reference_time, cleanup) == {:ok, 1}
    assert_receive {:cleanup_event, %{claims_removed: 1}, %{result: :ok}}
    assert Process.alive?(cleanup)
  end

  test "rejects an invalid interval clearly" do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      assert ReplayCleanup.start_link(name: nil, interval: 0) ==
               {:error, {:invalid_interval, 0}}
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp start_cleanup do
    cleanup = start_supervised!({ReplayCleanup, [name: nil, interval: :infinity]})
    :ok = Sandbox.allow(Repo, self(), cleanup)
    cleanup
  end

  defp insert_claim(fingerprint, expires_at) do
    %WebhookReplayClaim{}
    |> WebhookReplayClaim.changeset(%{fingerprint: fingerprint, expires_at: expires_at})
    |> Repo.insert!()
  end

  defp attach_cleanup_event do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @cleanup_completed_event,
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:cleanup_event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp refute_sensitive_keys(values) do
    refute Enum.any?(@sensitive_keys, &Map.has_key?(values, &1))
  end
end
