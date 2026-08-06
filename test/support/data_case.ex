defmodule Ironhold.DataCase do
  @moduledoc """
  Test case for code that needs access to the database.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Ironhold.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ironhold.DataCase
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    owner = Sandbox.start_owner!(Ironhold.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
