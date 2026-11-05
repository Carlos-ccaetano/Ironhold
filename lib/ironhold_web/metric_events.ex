defmodule IronholdWeb.MetricEvents do
  @moduledoc """
  Allowlisted library events for the project's metric reporters.

  Raw Phoenix/Ecto events remain internal and must not be exported directly.
  """

  @events %{
    [:phoenix, :endpoint, :start] => [:system_time],
    [:phoenix, :endpoint, :stop] => [:duration],
    [:phoenix, :router_dispatch, :start] => [:system_time],
    [:phoenix, :router_dispatch, :stop] => [:duration],
    [:phoenix, :router_dispatch, :exception] => [:duration],
    [:ironhold, :repo, :query] => [
      :total_time,
      :decode_time,
      :query_time,
      :queue_time,
      :idle_time
    ]
  }

  def attach do
    routes = IronholdWeb.Router.__routes__() |> Enum.map(& &1.path) |> MapSet.new()
    detach()
    :telemetry.attach_many(__MODULE__, Map.keys(@events), &__MODULE__.handle_event/4, routes)
  end

  def detach, do: :telemetry.detach(__MODULE__)

  def metric(%{event_name: [:phoenix | suffix]} = metric) do
    %{metric | event_name: [:ironhold, :observability, :phoenix | suffix]}
  end

  def metric(%{event_name: [:ironhold, :repo, :query]} = metric) do
    %{metric | event_name: [:ironhold, :observability, :repo, :query]}
  end

  def metric(metric), do: metric

  @doc false
  def handle_event(event, measurements, metadata, routes)
      when is_map(measurements) and is_map(metadata) do
    with {:ok, keys} <- Map.fetch(@events, event),
         true <- owned?(event, metadata) do
      values =
        for key <- keys,
            value = Map.get(measurements, key),
            is_integer(value) and value >= 0,
            into: %{},
            do: {key, value}

      :telemetry.execute(export_event(event), values, labels(event, metadata, routes))
    else
      _ -> :ok
    end
  end

  def handle_event(_event, _measurements, _metadata, _routes), do: :ok

  defp owned?([:phoenix, source, _], metadata) when source in [:endpoint, :router_dispatch] do
    match?(%{conn: %Plug.Conn{private: %{phoenix_endpoint: IronholdWeb.Endpoint}}}, metadata)
  end

  defp owned?([:ironhold, :repo, :query], metadata), do: Map.get(metadata, :repo) == Ironhold.Repo
  defp owned?(_event, _metadata), do: false

  defp export_event([:phoenix | suffix]), do: [:ironhold, :observability, :phoenix | suffix]
  defp export_event([:ironhold, :repo, :query]), do: [:ironhold, :observability, :repo, :query]

  defp labels([:phoenix, :router_dispatch, phase], metadata, routes) do
    route = Map.get(metadata, :route)
    labels = %{route: if(MapSet.member?(routes, route), do: route, else: "unmatched")}

    if phase == :exception do
      kind = Map.get(metadata, :kind)
      Map.put(labels, :kind, if(kind in [:error, :exit, :throw], do: kind, else: :unknown))
    else
      labels
    end
  end

  defp labels(_event, _metadata, _routes), do: %{}
end
