defmodule Ziwoas.LiveState do
  @moduledoc """
  The live picture of the house (Rails' `LiveState`): every configured plug
  with its latest measurement, and the energy flow built from the consumers'
  draw and the inverter's fresh reading. `now` is truncated to whole seconds,
  as Rails' `Time.zone.at(now.to_i)` does.
  """
  alias Ziwoas.{Config, EnergyFlow}
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias Ziwoas.Solakon.Reading

  defmodule Row do
    @moduledoc false
    @enforce_keys [:id, :name, :role, :online, :apower_w, :last_seen_ts]
    defstruct @enforce_keys
  end

  @enforce_keys [:plugs, :energy_flow]
  defstruct @enforce_keys

  @type t :: %__MODULE__{plugs: [Row.t()], energy_flow: EnergyFlow.t()}

  @spec build(Config.t(), DateTime.t(), keyword) :: t
  def build(%Config{} = config, now, opts \\ []) do
    offline_after_s = Keyword.get(opts, :offline_after_s, Measurement.offline_after_s())
    stale_after_s = Keyword.get(opts, :stale_after_s, Reading.stale_after_s())
    now = now |> DateTime.truncate(:second) |> DateTime.to_unix() |> DateTime.from_unix!()
    roster = Config.plug_roster(config)

    measurements =
      Measurement.for_plugs(Roster.ids(roster), DateTime.to_unix(now), offline_after_s)

    reading =
      if config.solakon && config.solakon.monitoring_enabled,
        do: Reading.latest_fresh(now, stale_after_s)

    %__MODULE__{
      plugs: Enum.map(roster.all, &row(&1, measurements[&1.id])),
      energy_flow:
        EnergyFlow.build(Measurement.total_w(measurements, Roster.consumer_ids(roster)), reading)
    }
  end

  defp row(plug, measurement) do
    %Row{
      id: plug.id,
      name: plug.name,
      role: plug.role,
      online: not measurement.offline,
      apower_w: Measurement.reported_watt(measurement),
      last_seen_ts: measurement.last_seen_ts
    }
  end
end
