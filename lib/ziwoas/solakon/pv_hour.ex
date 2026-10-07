defmodule Ziwoas.Solakon.PvHour do
  @moduledoc "Hourly PV power averages (`solakon_pv_hours`). No timestamps columns."
  use Ziwoas.Schema

  schema "solakon_pv_hours" do
    field :pv1_power_w, :float
    field :pv2_power_w, :float
    field :pv3_power_w, :float
    field :pv4_power_w, :float
    field :pv_power_w, :float
    field :reading_count, :integer
    field :started_at, Ziwoas.Ecto.RailsDateTime
  end
end
