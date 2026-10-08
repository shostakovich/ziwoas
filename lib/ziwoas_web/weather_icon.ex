defmodule ZiwoasWeb.WeatherIcon do
  @moduledoc false
  alias Ziwoas.Weather
  alias Ziwoas.Weather.Segment

  @labels %{
    "clear" => "klar",
    "partly-cloudy" => "teils bewölkt",
    "cloudy" => "bewölkt",
    "fog" => "Nebel",
    "wind" => "windig",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter",
    "unknown" => "Wetter"
  }

  @spec asset_name(Segment.t() | %{icon: String.t() | nil, daytime: String.t() | nil}) ::
          String.t()
  def asset_name(%Segment{} = segment),
    do: asset_name(Segment.dominant_icon(segment), Segment.dominant_daytime(segment))

  def asset_name(%{icon: icon, daytime: daytime}), do: asset_name(icon, daytime)

  @spec asset_name(String.t() | nil, String.t() | nil) :: String.t()
  def asset_name(icon, daytime) do
    base = icon |> Weather.base_icon() |> String.replace("-", "_")
    "weather_#{base}_#{if daytime == "night", do: "night", else: "day"}.webp"
  end

  @spec label(String.t() | nil) :: String.t()
  def label(icon), do: Map.fetch!(@labels, Weather.base_icon(icon))

  @spec dashboard(map | nil) :: {String.t(), String.t()}
  def dashboard(nil), do: {"icon_sonne.webp", "Sonne"}

  def dashboard(%{icon: icon} = record) do
    alt = if is_binary(icon) and String.trim(icon) != "", do: icon, else: "Sonne"
    {asset_name(record), alt}
  end
end
