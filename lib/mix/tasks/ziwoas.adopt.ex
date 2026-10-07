defmodule Mix.Tasks.Ziwoas.Adopt do
  @shortdoc "Takes over the database the Rails app left behind"

  @moduledoc """
  Drops Rails' migration bookkeeping from the configured database so Ecto's migrator
  can take over (`Ziwoas.Release.adopt_rails_database!/0`); a no-op on any other
  database. `mix ecto.migrate` runs it first.

      ZIWOAS_DB=storage/production.sqlite3 mix ziwoas.adopt
  """
  use Mix.Task

  @requirements ["app.config"]

  @impl true
  def run(_args) do
    Ziwoas.Release.adopt_rails_database!()
    :ok
  end
end
