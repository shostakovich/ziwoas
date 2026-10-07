defmodule Ziwoas.Weather.Record do
  @moduledoc "One observed or forecast weather data point for a location (`weather_records`)."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "weather_records" do
    field :cloud_cover, :integer
    field :condition, :string
    field :daytime, :string
    field :dew_point, :float
    field :icon, :string
    field :kind, :string
    field :lat, :float
    field :lon, :float
    field :precipitation, :float
    field :precipitation_probability, :integer
    field :precipitation_probability_6h, :integer
    field :pressure_msl, :float
    field :relative_humidity, :integer
    field :solar, :float
    field :source_id, :integer
    field :sunshine, :float
    field :temperature, :float
    field :timestamp, :utc_datetime_usec
    field :visibility, :integer
    field :wind_direction, :integer
    field :wind_gust_direction, :integer
    field :wind_gust_speed, :float
    field :wind_speed, :float
    timestamps()
  end
end
