defmodule Ziwoas.Sensors.Reading do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @measurements [
    :temperature,
    :humidity,
    :co2,
    :pm1_0,
    :pm2_5,
    :pm4_0,
    :pm10,
    :voc_index,
    :nox_index,
    :device_status,
    :battery_pct,
    :firmware_version
  ]

  schema "sensor_readings" do
    field :battery_pct, :integer
    field :co2, :integer
    field :device_id, :string
    field :device_status, :integer
    field :firmware_version, :string
    field :humidity, :float
    field :nox_index, :integer
    field :pm1_0, :float
    field :pm2_5, :float
    field :pm4_0, :float
    field :pm10, :float
    field :taken_at, :utc_datetime_usec
    field :temperature, :float
    field :voc_index, :integer
    timestamps()
  end

  @spec changeset(String.t(), DateTime.t(), map) :: Ecto.Changeset.t()
  def changeset(device_id, taken_at, measurements) do
    measurements =
      Map.new(measurements, fn
        {key, value} when key in [:co2, :battery_pct] and is_float(value) -> {key, round(value)}
        pair -> pair
      end)

    %__MODULE__{device_id: device_id, taken_at: taken_at}
    |> cast(measurements, @measurements)
    |> validate_required([:device_id, :taken_at])
  end
end
