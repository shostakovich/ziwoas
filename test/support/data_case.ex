defmodule Ziwoas.DataCase do
  @moduledoc false
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
      valid_from: Date.from_iso8601!(valid_from),
      eur_per_kwh: Decimal.new(eur_per_kwh)
    })
  end

  def usec(%DateTime{} = time) do
    {:ok, time} = Ecto.Type.cast(:utc_datetime_usec, time)
    time
  end

  def berlin_midnight(date), do: Ziwoas.LocalDay.midnight_unix(date, "Europe/Berlin")
end
