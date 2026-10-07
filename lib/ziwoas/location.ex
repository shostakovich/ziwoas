defmodule Ziwoas.Location do
  @moduledoc "Where the house stands: an IANA time zone, and coordinates when configured."

  @enforce_keys [:timezone]
  defstruct [:timezone, :lat, :lon]

  @type t :: %__MODULE__{timezone: String.t(), lat: float | nil, lon: float | nil}

  @spec new(String.t(), keyword) :: t
  def new(timezone, opts \\ []) do
    case DateTime.now(timezone) do
      {:ok, _} -> %__MODULE__{timezone: timezone, lat: opts[:lat], lon: opts[:lon]}
      {:error, _} -> raise ArgumentError, "'#{timezone}' is not a valid IANA timezone"
    end
  end

  @spec located?(t) :: boolean
  def located?(%__MODULE__{lat: lat, lon: lon}), do: not is_nil(lat) and not is_nil(lon)
end
