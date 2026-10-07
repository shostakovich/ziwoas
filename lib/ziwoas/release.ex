defmodule Ziwoas.Release do
  @moduledoc "Database tasks a release runs without Mix (`bin/migrate`)."

  @app :ziwoas

  # One connection is all the migrator needs on SQLite, and on an empty file a second
  # one would race the first to switch it to WAL ("database is locked" while connecting).
  @migrator_opts [pool_size: 1]

  @doc "Runs every pending migration."
  def migrate do
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true), @migrator_opts)
    end

    :ok
  end
end
