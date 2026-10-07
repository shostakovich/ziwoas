defmodule Ziwoas.Weather.Segment do
  @moduledoc false
  alias Ziwoas.Weather
  alias Ziwoas.Weather.Record

  @enforce_keys [:label, :hours, :records]
  defstruct @enforce_keys

  @type t :: %__MODULE__{label: atom, hours: Range.t(), records: [Record.t()]}

  @icon_severity ~w[thunderstorm hail snow sleet rain wind fog cloudy partly-cloudy clear unknown]

  @spec complete?(t) :: boolean
  def complete?(%__MODULE__{hours: hours, records: records}),
    do: length(records) >= Range.size(hours)

  @spec temp_min(t) :: float | nil
  def temp_min(%__MODULE__{records: records}), do: Weather.min_of(records, :temperature)

  @spec temp_max(t) :: float | nil
  def temp_max(%__MODULE__{records: records}), do: Weather.max_of(records, :temperature)

  @spec precip_sum(t) :: number
  def precip_sum(%__MODULE__{records: records}), do: Weather.precip_sum(records)

  @spec avg_solar_w_per_m2(t) :: float | nil
  def avg_solar_w_per_m2(%__MODULE__{records: records}) do
    case records |> Enum.map(&Weather.solar_w_per_m2/1) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Enum.sum(values) / length(values)
    end
  end

  @spec all_night?(t) :: boolean
  def all_night?(%__MODULE__{records: []}), do: false
  def all_night?(%__MODULE__{records: records}), do: Enum.all?(records, &(&1.daytime == "night"))

  @spec dominant_icon(t) :: String.t()
  def dominant_icon(%__MODULE__{records: []}), do: "unknown"

  def dominant_icon(%__MODULE__{records: records}) do
    records
    |> Enum.map(&Weather.base_icon(&1.icon))
    |> Enum.min_by(&severity/1)
  end

  @spec dominant_daytime(t) :: String.t()
  def dominant_daytime(%__MODULE__{records: records} = segment) do
    target = dominant_icon(segment)

    case Enum.find(records, &(Weather.base_icon(&1.icon) == target)) || List.first(records) do
      %Record{daytime: daytime} when is_binary(daytime) -> daytime
      _ -> "day"
    end
  end

  defp severity(icon) do
    Enum.find_index(@icon_severity, &(&1 == icon)) || length(@icon_severity)
  end
end
