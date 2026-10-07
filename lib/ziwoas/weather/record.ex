defmodule Ziwoas.Weather.Record do
  @moduledoc "One observed or forecast weather data point for a location (`weather_records`)."
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds ~w(current forecast historic)
  @integers ~w(source_id wind_direction cloud_cover relative_humidity visibility
               wind_gust_direction precipitation_probability precipitation_probability_6h)a
  @fields ~w(kind lat lon timestamp precipitation pressure_msl sunshine temperature wind_speed
             dew_point wind_gust_speed solar condition icon daytime)a ++ @integers

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

  @doc """
  A record from Bright Sky's values (`Ziwoas.Weather.BrightskyClient`); whole
  numbers given as floats are rounded.
  """
  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(record \\ %__MODULE__{}, attrs) do
    attrs =
      Map.new(attrs, fn
        {key, value} when key in @integers and is_float(value) -> {key, round(value)}
        pair -> pair
      end)

    record
    |> cast(attrs, @fields)
    |> validate_required([:kind, :lat, :lon, :timestamp, :daytime])
    |> validate_inclusion(:kind, @kinds)
  end
end
