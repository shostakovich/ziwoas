defmodule Ziwoas.Weather.Icon do
  @moduledoc "Bright Sky icon names to asset names."

  @icons ~w[clear partly-cloudy cloudy fog wind rain sleet snow hail thunderstorm unknown]

  @spec asset_name(String.t() | nil, String.t() | nil) :: String.t()
  def asset_name(icon, daytime) do
    base = icon |> normalized_icon() |> String.replace("-", "_")
    "weather_#{base}_#{normalized_daytime(daytime)}.webp"
  end

  @doc "\"day\" or \"night\": the icon's suffix when it has one, else where the sun stands."
  @spec daytime_for(String.t() | nil, DateTime.t(), Ziwoas.Location.t()) :: String.t()
  def daytime_for(icon, timestamp, location) do
    icon = icon || ""

    cond do
      String.ends_with?(icon, "-day") -> "day"
      String.ends_with?(icon, "-night") -> "night"
      Ziwoas.Sun.daytime?(location, timestamp) -> "day"
      true -> "night"
    end
  end

  @doc "The icon without its -day/-night suffix; anything unknown is \"unknown\"."
  @spec normalized_icon(String.t() | nil) :: String.t()
  def normalized_icon(icon) do
    raw =
      (icon || "")
      |> String.replace_suffix("-day", "")
      |> String.replace_suffix("-night", "")

    if raw in @icons, do: raw, else: "unknown"
  end

  @spec normalized_daytime(String.t() | nil) :: String.t()
  def normalized_daytime("night"), do: "night"
  def normalized_daytime(_daytime), do: "day"
end
