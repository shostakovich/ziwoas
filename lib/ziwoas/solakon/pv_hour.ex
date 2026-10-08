defmodule Ziwoas.Solakon.PvHour do
  @moduledoc false
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "solakon_pv_hours" do
    field :pv1_power_w, :float
    field :pv2_power_w, :float
    field :pv3_power_w, :float
    field :pv4_power_w, :float
    field :pv_power_w, :float
    field :reading_count, :integer
    field :started_at, :utc_datetime_usec
  end
end
