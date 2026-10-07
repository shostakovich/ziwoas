defmodule Ziwoas.Sensors.Reading do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @measurements [:temperature, :humidity, :co2, :battery_pct, :firmware_version]

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

  @spec changeset(String.t(), DateTime.t(), map) :: Ecto.Changeset.t()
  def changeset(device_id, taken_at, measurements) do
    measurements =
      Map.new(measurements, fn
        {key, value} when key in [:humidity, :co2, :battery_pct] and is_float(value) ->
          {key, round(value)}

        pair ->
          pair
      end)

    %__MODULE__{device_id: device_id, taken_at: taken_at}
    |> cast(measurements, @measurements)
    |> validate_required([:device_id, :taken_at])
  end
end
