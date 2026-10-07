defmodule Ziwoas.Sensors.Reading do
  @moduledoc "One reading of an air sensor (`sensor_readings`)."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "sensor_readings" do
    field :battery_pct, :integer
    field :co2, :integer
    field :device_id, :string
    field :firmware_version, :string
    field :humidity, :integer
    field :taken_at, :utc_datetime_usec
    field :temperature, :float
    timestamps()
  end
end
