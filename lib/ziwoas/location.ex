defmodule Ziwoas.Location do
  @moduledoc """
  Where the house stands: an IANA time zone, and coordinates when configured
  (`location:` in the device config).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ziwoas.Config.Types

  @primary_key false
  embedded_schema do
    field :timezone, Types.Text
    field :lat, Types.Real
    field :lon, Types.Real
  end

  @type t :: %__MODULE__{timezone: String.t(), lat: float | nil, lon: float | nil}

  @spec new(String.t(), keyword) :: t
  def new(timezone, opts \\ []) do
    if valid_zone?(timezone),
      do: %__MODULE__{timezone: timezone, lat: opts[:lat], lon: opts[:lon]},
      else: raise(ArgumentError, "'#{timezone}' is not a valid IANA timezone")
  end

  @spec located?(t) :: boolean
  def located?(%__MODULE__{lat: lat, lon: lon}), do: not is_nil(lat) and not is_nil(lon)

  @doc false
  def changeset(location, params) do
    location
    |> cast(params, [:timezone, :lat, :lon], message: &Types.cast_message/2)
    |> validate_required([:timezone], message: "is required")
    |> validate_change(:timezone, fn :timezone, zone ->
      if valid_zone?(zone), do: [], else: [timezone: "'#{zone}' is not a valid IANA timezone"]
    end)
    |> validate_coordinates(params)
  end

  # Both or neither: without a pair there is no sun and no weather.
  defp validate_coordinates(changeset, params) do
    if Map.has_key?(params, "lat") or Map.has_key?(params, "lon") do
      changeset
      |> validate_required([:lat, :lon], message: "must be a number")
      |> validate_number(:lat,
        greater_than_or_equal_to: -90,
        less_than_or_equal_to: 90,
        message: "must be between -90 and 90"
      )
      |> validate_number(:lon,
        greater_than_or_equal_to: -180,
        less_than_or_equal_to: 180,
        message: "must be between -180 and 180"
      )
    else
      changeset
    end
  end

  defp valid_zone?(zone), do: match?({:ok, _}, DateTime.now(zone))
end
