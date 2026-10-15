defmodule ZiwoasWeb.Plush do
  @moduledoc """
  The plush images behind `<.plush name="…">`. Names follow Lucide where one fits; on/off
  pairs name the off image `<name>-off`, weather images `weather-<condition>-<day|night>`.
  """
  @behaviour Setzkasten.Plush
  use ZiwoasWeb, :verified_routes

  @files %{
    "house" => "nav_dashboard_plush.webp",
    "sun" => "icon_sonne.webp",
    "plug" => "nav_switches_plush.webp",
    "chart-column" => "nav_reports_plush.webp",
    "cloud-sun-rain" => "nav_weather_plush.webp",
    "traffic-light" => "nav_sensors_plush.webp",
    "settings" => "settings_plush.webp",
    "household" => "icon_haus.webp",
    "utility-pole" => "icon_netz.webp",
    "zipfelmaus" => "zipfelmaus.webp",
    "shelly-plug" => "switch_plush_on.webp",
    "shelly-plug-off" => "switch_plush_off.webp",
    "battery" => "solakon_battery_normal.webp",
    "battery-charging" => "solakon_battery_charging.webp",
    "battery-low" => "solakon_battery_low.webp",
    "battery-warning" => "solakon_battery_fault.webp",
    "battery-hot" => "solakon_battery_hot.webp",
    "battery-cold" => "solakon_battery_cold.webp",
    "lamp" => "lamp_generic_on.webp",
    "lamp-off" => "lamp_generic_off.webp",
    "lamp-ceiling" => "lamp_ceiling_on.webp",
    "lamp-ceiling-off" => "lamp_ceiling_off.webp",
    "lamp-floor" => "lamp_floorlamp_on.webp",
    "lamp-floor-off" => "lamp_floorlamp_off.webp",
    "lamp-sconce" => "lamp_sconce_on.webp",
    "lamp-sconce-off" => "lamp_sconce_off.webp",
    "lamp-uplighter" => "lamp_uplighter_on.webp",
    "lamp-uplighter-off" => "lamp_uplighter_off.webp"
  }

  @weather ~w(clear partly-cloudy cloudy fog wind rain sleet snow hail thunderstorm unknown)

  @files Map.merge(
           @files,
           for(
             condition <- @weather,
             daytime <- ~w(day night),
             into: %{},
             do:
               {"weather-#{condition}-#{daytime}",
                "weather_#{String.replace(condition, "-", "_")}_#{daytime}.webp"}
           )
         )

  @impl true
  def src(name, :light) do
    case @files do
      %{^name => file} -> ~p"/images/#{file}"
      %{} -> nil
    end
  end

  def src(_name, _variant), do: nil

  @doc false
  def names, do: Map.keys(@files)
end
