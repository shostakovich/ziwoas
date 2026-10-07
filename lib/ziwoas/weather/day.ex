defmodule Ziwoas.Weather.Day do
  @moduledoc "One forecast day and its four segments."
  alias Ziwoas.Weather
  alias Ziwoas.Weather.{Record, Segment}

  @enforce_keys [:date, :records, :zone]
  defstruct @enforce_keys

  @type t :: %__MODULE__{date: Date.t(), records: [Record.t()], zone: String.t()}

  @segments [
    night: 0..5//1,
    morning: 6..11//1,
    afternoon: 12..17//1,
    evening: 18..23//1
  ]

  @spec temp_min(t) :: float | nil
  def temp_min(%__MODULE__{records: records}), do: Weather.min_of(records, :temperature)

  @spec temp_max(t) :: float | nil
  def temp_max(%__MODULE__{records: records}), do: Weather.max_of(records, :temperature)

  @spec precip_sum(t) :: number
  def precip_sum(%__MODULE__{records: records}), do: Weather.precip_sum(records)

  @doc "The day's peak `solar` (kWh/m² over a 60-minute forecast period) as W/m²."
  @spec solar_peak_w_per_m2(t) :: float | nil
  def solar_peak_w_per_m2(%__MODULE__{records: records}) do
    case Weather.max_of(records, :solar) do
      nil -> nil
      peak -> peak * 1000.0
    end
  end

  @doc "Night, morning, afternoon and evening by local hour; a segment may be empty."
  @spec segments(t) :: [Segment.t()]
  def segments(%__MODULE__{records: records, zone: zone}) do
    by_label =
      Enum.group_by(records, &segment_label(Weather.local_time(&1, zone).hour))

    for {label, hours} <- @segments,
        do: %Segment{label: label, hours: hours, records: Map.get(by_label, label, [])}
  end

  defp segment_label(hour),
    do: Enum.find_value(@segments, fn {label, hours} -> if hour in hours, do: label end)
end
