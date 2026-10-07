defmodule Ziwoas.DataCase do
  @moduledoc """
  Tests that touch the database. Each test runs inside a transaction of the SQL
  sandbox that is rolled back when it ends, so every test starts from the empty,
  migrated `tmp/test.sqlite3`.

      use Ziwoas.DataCase

  SQLite allows one write transaction at a time, which the sandbox holds for the whole
  test, so these tests cannot run async: `async: true` raises.

  The test process owns the connection. Processes it starts with `$callers` set (a
  LiveView under `Phoenix.LiveViewTest`, a `Task`) use it too; any other process (a
  `start_supervised` GenServer) needs `Ecto.Adapters.SQL.Sandbox.allow/3`, or the
  module tag `@moduletag :shared_sandbox` when it queries before the test can allow it.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Ziwoas.Repo

  using opts do
    check_sync!(__CALLER__.module, opts)

    quote do
      import Ziwoas.DataCase
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc false
  def check_sync!(module, opts) do
    if Keyword.get(opts, :async, false) do
      raise ArgumentError,
            "#{inspect(module)} touches the database and cannot run async: SQLite allows " <>
              "one write transaction at a time, and the SQL sandbox holds it for the whole " <>
              "test. Drop `async: true`."
    end
  end

  @doc "Starts the sandbox owner of the test's connection; it stops when the test ends."
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Repo, shared: Map.has_key?(tags, :shared_sandbox))
    ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)
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

  @doc """
  `time` in UTC with microsecond precision, the form a `:utc_datetime_usec` field takes
  when a struct goes into `Repo.insert!/1` without a changeset.
  """
  def usec(%DateTime{} = time) do
    {:ok, time} = Ecto.Type.cast(:utc_datetime_usec, time)
    time
  end

  @doc "Local midnight of `date` in Berlin, Unix seconds."
  def berlin_midnight(date), do: Ziwoas.LocalDay.midnight_unix(date, "Europe/Berlin")
end
