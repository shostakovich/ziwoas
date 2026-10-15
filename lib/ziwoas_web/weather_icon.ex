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

  @spec asset_name(String.t() | nil, String.t() | nil) :: String.t()
  def asset_name(icon, daytime) do
    base = icon |> Weather.base_icon() |> String.replace("-", "_")
    "weather_#{base}_#{if daytime == "night", do: "night", else: "day"}.webp"
  end

  @doc "The `<.plush>` name of a record's or a segment's weather, as `ZiwoasWeb.Plush` lists it."
  @spec plush_name(Segment.t() | %{icon: String.t() | nil, daytime: String.t() | nil}) ::
          String.t()
  def plush_name(%Segment{} = segment),
    do: plush_name(Segment.dominant_icon(segment), Segment.prevailing_daytime(segment))

  def plush_name(%{icon: icon, daytime: daytime}), do: plush_name(icon, daytime)

  @spec plush_name(String.t() | nil, String.t() | nil) :: String.t()
  def plush_name(icon, daytime),
    do: "weather-#{Weather.base_icon(icon)}-#{if daytime == "night", do: "night", else: "day"}"

  @doc "The current weather's plush: night by the record, or once the sun is down by the clock."
  @spec current_plush_name(%{icon: String.t() | nil, daytime: String.t() | nil}, boolean) ::
          String.t()
  def current_plush_name(%{icon: icon, daytime: daytime}, daylight),
    do: plush_name(icon, if(daytime == "night" or not daylight, do: "night", else: "day"))

  @spec label(String.t() | nil) :: String.t()
  def label(icon), do: Map.fetch!(@labels, Weather.base_icon(icon))

  @spec dashboard(map | nil) :: {String.t(), String.t()}
  def dashboard(nil), do: {"icon_sonne.webp", "Sonne"}

  def dashboard(%{icon: icon, daytime: daytime}) do
    alt = if is_binary(icon) and String.trim(icon) != "", do: icon, else: "Sonne"
    {asset_name(icon, daytime), alt}
  end
end
