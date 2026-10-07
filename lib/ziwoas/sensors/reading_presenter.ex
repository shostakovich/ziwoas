defmodule Ziwoas.Sensors.ReadingPresenter do
  @moduledoc """
  How a sensor's latest reading reads:
  CO₂ traffic light, low battery, age and whether the sensor is offline.
  A missing reading is offline and has no age.
  """
  alias Ziwoas.Sensors.Reading

  @co2_warn_ppm 1000
  @co2_bad_ppm 1400
  @battery_low_pct 20
  @offline_after_s 30 * 60

  @doc "From here on CO₂ is `:warn` (ppm)."
  def co2_warn_ppm, do: @co2_warn_ppm

  @doc "Above this CO₂ is `:bad` (ppm)."
  def co2_bad_ppm, do: @co2_bad_ppm

  @spec co2_level(Reading.t() | nil) :: :good | :warn | :bad | nil
  def co2_level(%Reading{co2: ppm}) when is_integer(ppm) do
    cond do
      ppm > @co2_bad_ppm -> :bad
      ppm >= @co2_warn_ppm -> :warn
      true -> :good
    end
  end

  def co2_level(_reading), do: nil

  @spec battery_low?(Reading.t() | nil) :: boolean
  def battery_low?(%Reading{battery_pct: pct}) when is_integer(pct), do: pct <= @battery_low_pct
  def battery_low?(_reading), do: false

  @doc "\"vor 4 Min\": whole seconds, minutes or hours since the reading, truncated."
  @spec age_label(Reading.t() | nil, DateTime.t()) :: String.t()
  def age_label(nil, _now), do: "—"

  def age_label(%Reading{} = reading, now) do
    delta = div(age_us(reading, now), 1_000_000)

    cond do
      delta < 60 -> "vor #{delta} s"
      delta < 3600 -> "vor #{div(delta, 60)} Min"
      true -> "vor #{div(delta, 3600)} h"
    end
  end

  @spec offline?(Reading.t() | nil, DateTime.t()) :: boolean
  def offline?(nil, _now), do: true
  def offline?(%Reading{} = reading, now), do: age_us(reading, now) > @offline_after_s * 1_000_000

  defp age_us(%Reading{taken_at: taken_at}, now), do: DateTime.diff(now, taken_at, :microsecond)
end
