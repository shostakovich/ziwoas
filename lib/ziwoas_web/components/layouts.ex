defmodule ZiwoasWeb.Layouts do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Config

  embed_templates "layouts/*"

  attr :current_path, :string, required: true
  attr :width, :atom, default: :narrow, values: [:narrow, :default]
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :current, section(assigns.current_path))

    ~H"""
    <.app_shell layout={:topbar} current={@current} width={@width} bar_width={:default}>
      <:brand>
        <.link
          navigate={~p"/"}
          aria-label="Zipfelmaus — Startseite"
          class="flex min-w-0 items-center gap-2"
        >
          <.plush name="zipfelmaus" size={:lg} />
          <span class="flex min-w-0 flex-col leading-tight">
            <span class="truncate">Zipfelmaus</span>
            <span class="truncate text-xs font-normal text-base-content/70">
              Wohnungsautomatisierung
            </span>
          </span>
        </.link>
      </:brand>
      <:nav key={:home} label="Home" plush="house" navigate={~p"/"} />
      <:nav key={:solakon} label="PV" plush="sun" navigate={~p"/solakon"} />
      <:nav key={:switches} label="Schalten" plush="plug" navigate={~p"/switches"} />
      <:nav key={:reports} label="Berichte" plush="chart-column" navigate={~p"/reports"} />
      <:nav key={:weather} label="Wetter" plush="cloud-sun-rain" navigate={~p"/weather"} />
      <:nav key={:sensors} label="Sensoren" plush="traffic-light" navigate={~p"/sensors"} />
      <:account><.theme_toggle compact /></:account>
      {render_slot(@inner_block)}
    </.app_shell>

    <.flash_group flash={@flash} />
    <.confirm_dialog />
    """
  end

  def time_zone do
    case Config.fetch() do
      {:ok, config} -> config.location.timezone
      {:error, _message} -> nil
    end
  end

  # A lamp's page lives under /lights but is reached from Schalten.
  @sections %{
    "solakon" => :solakon,
    "switches" => :switches,
    "lights" => :switches,
    "reports" => :reports,
    "weather" => :weather,
    "sensors" => :sensors
  }

  defp section(path) do
    case String.split(path, "/", trim: true) do
      [] -> :home
      [first | _] -> @sections[first]
    end
  end
end
