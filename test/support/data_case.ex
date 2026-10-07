defmodule Ziwoas.DataCase do
  @moduledoc """
  Tests that write rows: every module gets its own writable SQLite with the Rails
  schema (`Ziwoas.RailsFixture`, no rows), every test starts from empty tables.
  The repo is the process's dynamic repo, so code under test in the same process
  (including a controller dispatched by `Phoenix.ConnTest`) reads these rows.

      use Ziwoas.DataCase, async: true

  `ZiwoasWeb.ConnCase` takes `db: true` for the same.
  """
  use ExUnit.CaseTemplate

  alias Ziwoas.Repo

  using do
    quote do
      import Ziwoas.DataCase
    end
  end

  setup_all context, do: start_db!(context)
  setup context, do: checkout!(context)

  @doc "A fresh database file for the test module and a writable repo on it."
  def start_db!(%{module: module}) do
    name = module |> Atom.to_string() |> String.replace(~r/\W+/, "_")

    path =
      Ziwoas.RailsFixture.build!(Path.expand("../../tmp/data/#{name}.sqlite3", __DIR__),
        rows: false
      )

    repo =
      ExUnit.Callbacks.start_supervised!(
        {Repo, name: nil, database: path, writable: true, pool_size: 1}
      )

    %{repo: repo}
  end

  @doc "Points the test process at the module's repo and empties every table."
  def checkout!(%{repo: repo}) do
    Repo.put_dynamic_repo(repo)

    %{rows: tables} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      )

    for [table] <- tables, do: Repo.query!(~s(DELETE FROM "#{table}"))
    ExUnit.Callbacks.on_exit(fn -> Ziwoas.Clock.unfreeze() end)
    :ok
  end

  def insert_sample!(plug_id, ts, apower_w, aenergy_wh) do
    Repo.insert!(%Ziwoas.Plugs.Sample{
      plug_id: plug_id,
      ts: ts,
      apower_w: apower_w * 1.0,
      aenergy_wh: aenergy_wh * 1.0
    })
  end

  def insert_price!(valid_from, eur_per_kwh) do
    Repo.insert!(%Ziwoas.Economics.ElectricityPrice{
      valid_from: valid_from,
      eur_per_kwh: Decimal.new(eur_per_kwh)
    })
  end

  @doc "Local midnight of `date` in Berlin, Unix seconds."
  def berlin_midnight(date), do: Ziwoas.LocalDay.midnight_unix(date, "Europe/Berlin")
end
