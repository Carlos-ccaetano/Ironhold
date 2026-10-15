defmodule Ironhold.Webhooks.ReplayCleanup do
  @moduledoc """
  Periodically removes expired webhook replay claims.
  """

  use GenServer

  require Logger

  alias Ironhold.Webhooks

  @cleanup_message :prune_expired_replay_claims

  def start_link(opts \\ []) do
    opts = Keyword.merge(Application.get_env(:ironhold, __MODULE__, []), opts)
    name = Keyword.get(opts, :name, __MODULE__)
    server_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  def run_now(reference_time, server \\ __MODULE__) do
    GenServer.call(server, {:run, reference_time})
  end

  @impl true
  def init(opts) do
    case Keyword.fetch(opts, :interval) do
      {:ok, interval} when is_integer(interval) and interval > 0 ->
        schedule_next(interval)
        {:ok, interval}

      {:ok, :infinity} ->
        {:ok, :infinity}

      {:ok, interval} ->
        {:stop, {:invalid_interval, interval}}

      :error ->
        {:stop, {:missing_configuration, :interval}}
    end
  end

  @impl true
  def handle_call({:run, reference_time}, _from, interval) do
    {:reply, prune(reference_time), interval}
  end

  @impl true
  def handle_info(@cleanup_message, interval) do
    _result = prune(DateTime.utc_now())
    schedule_next(interval)

    {:noreply, interval}
  end

  defp schedule_next(:infinity), do: :ok

  defp schedule_next(interval) do
    Process.send_after(self(), @cleanup_message, interval)
    :ok
  end

  defp prune(reference_time) do
    {:ok, Webhooks.prune_expired_replay_claims(reference_time)}
  rescue
    _exception ->
      Logger.warning("Replay claim cleanup failed; it will retry after the configured interval")
      {:error, :cleanup_failed}
  catch
    _kind, _reason ->
      Logger.warning("Replay claim cleanup failed; it will retry after the configured interval")
      {:error, :cleanup_failed}
  end
end
