defmodule IronholdWeb.HTTPAdapter do
  @moduledoc "Phoenix's Bandit adapter without request-bearing exception logs."

  def child_specs(endpoint, config) do
    config =
      Enum.map(config, fn
        {scheme, options} when scheme in [:http, :https] and is_list(options) ->
          http_options =
            options
            |> Keyword.get(:http_options, [])
            |> Keyword.merge(log_exceptions_with_status_codes: [], log_protocol_errors: false)

          {scheme, Keyword.put(options, :http_options, http_options)}

        other ->
          other
      end)

    Bandit.PhoenixAdapter.child_specs(endpoint, config)
  end

  defdelegate server_info(endpoint, scheme), to: Bandit.PhoenixAdapter
end
