defmodule Ziwoas.Solakon.Snapshot do
  @moduledoc """
  Full register snapshot of the Solakon inverter (`solakon_snapshots`), with
  the read side of Rails' `Solakon::Snapshot`: the four panels and the status.
  """
  use Ziwoas.Schema

  import Ecto.Query

  alias Ziwoas.{Repo, RubyNumeric}

  @type t :: %__MODULE__{}

  schema "solakon_snapshots" do
    field :active_power_w, :float
    field :alarm1, :integer
    field :alarm2, :integer
    field :alarm3, :integer
    field :battery_charge_total_kwh, :float
    field :battery_current_a, :float
    field :battery_discharge_total_kwh, :float
    field :battery_health_pct, :integer
    field :battery_min_temperature_c, :float
    field :battery_power_w, :float
    field :battery_soc_pct, :integer
    field :battery_temperature_c, :float
    field :battery_voltage_v, :float
    field :bms_faults, {:array, :integer}, default: []
    field :design_energy_wh, :float
    field :eps_enabled, :boolean
    field :eps_power_w, :float
    field :eps_voltage_v, :float
    field :full_charge_capacity_ah, :float
    field :grid_export_total_kwh, :float
    field :grid_import_total_kwh, :float
    field :grid_power_w, :float
    field :inverter_temperature_c, :float
    field :pv1_current_a, :float
    field :pv1_power_w, :float
    field :pv1_voltage_v, :float
    field :pv2_current_a, :float
    field :pv2_power_w, :float
    field :pv2_voltage_v, :float
    field :pv3_current_a, :float
    field :pv3_power_w, :float
    field :pv3_voltage_v, :float
    field :pv4_current_a, :float
    field :pv4_power_w, :float
    field :pv4_voltage_v, :float
    field :pv_total_kwh, :float
    field :remaining_energy_wh, :float
    field :status1, :integer
    field :status3, :integer
    field :taken_at, :utc_datetime_usec
    timestamps()
  end

  @doc """
  The row `Solakon::SnapshotJob` stores for a decoded
  `Ziwoas.Solakon.Client.read_snapshot/1` taken at `taken_at`.
  """
  @spec from_data(map, DateTime.t()) :: Ecto.Changeset.t()
  def from_data(data, taken_at) do
    panels =
      for panel <- data.panels,
          {field, value} <- [
            power_w: panel.power_w,
            voltage_v: panel.voltage_v,
            current_a: panel.current_a
          ],
          into: %{},
          do: {String.to_existing_atom("pv#{panel.index}_#{field}"), value}

    attrs =
      data
      |> Map.delete(:panels)
      |> Map.merge(panels)
      |> Map.put(:taken_at, taken_at)

    Ecto.Changeset.cast(%__MODULE__{}, attrs, Map.keys(attrs))
  end

  @spec latest() :: t | nil
  def latest, do: Repo.one(from s in __MODULE__, order_by: [desc: s.taken_at], limit: 1)

  @doc "Snapshots taken in `from..to` (both inclusive, SQL `BETWEEN`), oldest first."
  @spec in_range(DateTime.t(), DateTime.t()) :: [t]
  def in_range(from, to) do
    Repo.all(
      from s in __MODULE__,
        where: s.taken_at >= ^from and s.taken_at <= ^to,
        order_by: s.taken_at
    )
  end

  @doc "Every panel, wired or not: an idle one reports 0 W rather than going absent."
  @spec panels(t) :: [%{label: String.t(), power_w: float, voltage_v: float, current_a: float}]
  def panels(%__MODULE__{} = snapshot) do
    for {idx, power, voltage, current} <- [
          {1, snapshot.pv1_power_w, snapshot.pv1_voltage_v, snapshot.pv1_current_a},
          {2, snapshot.pv2_power_w, snapshot.pv2_voltage_v, snapshot.pv2_current_a},
          {3, snapshot.pv3_power_w, snapshot.pv3_voltage_v, snapshot.pv3_current_a},
          {4, snapshot.pv4_power_w, snapshot.pv4_voltage_v, snapshot.pv4_current_a}
        ] do
      %{
        label: "Panel #{idx}",
        power_w: RubyNumeric.to_f(power),
        voltage_v: RubyNumeric.to_f(voltage),
        current_a: RubyNumeric.to_f(current)
      }
    end
  end

  @doc "Total PV power: the panels' sum, never a figure stored in its own right."
  @spec pv_power_w(t) :: float
  def pv_power_w(%__MODULE__{} = s) do
    [s.pv1_power_w, s.pv2_power_w, s.pv3_power_w, s.pv4_power_w]
    |> Enum.map(&RubyNumeric.to_f/1)
    |> RubyNumeric.sum()
  end

  @spec status_messages(t) :: [String.t()]
  def status_messages(%__MODULE__{} = snapshot),
    do: Ziwoas.Solakon.status_messages(snapshot, snapshot.bms_faults || [])
end
