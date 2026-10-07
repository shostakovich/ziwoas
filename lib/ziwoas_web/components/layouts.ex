defmodule ZiwoasWeb.Layouts do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Config

  embed_templates "layouts/*"

  attr :look, :string, required: true
  attr :current_path, :string, required: true
  attr :main_class, :any, default: nil
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :navigation, navigation(assigns.current_path))

    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <div class="container pt-3">
      <header class="navbar navbar-expand px-3 app-header mb-3">
        <.link
          class="navbar-brand app-brand d-flex align-items-center py-0"
          aria-label="Zipfelmaus — Startseite"
          navigate={~p"/"}
        >
          <img
            alt=""
            class="app-brand-mascot"
            width="42"
            height="40"
            src={~p"/images/zipfelmaus.webp"}
          />
          <span class="app-brand-text" aria-hidden="true">
            <span class="app-brand-name">Zipfelmaus</span>
            <span class="app-brand-tagline">Wohnungs&shy;automatisierung</span>
          </span>
        </.link>
        <nav class="d-none d-lg-block me-auto" aria-label="Hauptnavigation">
          <ul class="navbar-nav nav-pills flex-nowrap">
            <li :for={item <- @navigation} class="nav-item">
              <.link
                class={["nav-link d-flex align-items-center gap-2 px-2", item.current && "active"]}
                aria-current={item.current && "page"}
                navigate={item.path}
              >
                <img alt="" class="app-nav-icon" aria-hidden="true" src={~p"/images/#{item.icon}"} />
                {item.label}
              </.link>
            </li>
          </ul>
        </nav>
        <div class="d-flex align-items-center ms-auto">
          <.look_toggle look={@look} />
        </div>
      </header>
    </div>

    <main class={["container app-main", @main_class]} id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>

    <nav class="navbar fixed-bottom pb-safe d-lg-none" aria-label="Tab-Leiste">
      <ul class="nav nav-pills nav-justified flex-nowrap w-100">
        <li :for={item <- @navigation} class="nav-item">
          <.link
            class={["nav-link d-flex flex-column align-items-center", item.current && "active"]}
            aria-current={item.current && "page"}
            navigate={item.path}
          >
            <img alt="" class="app-nav-icon" aria-hidden="true" src={~p"/images/#{item.icon}"} />
            <small>{item.label}</small>
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  attr :look, :string, required: true

  defp look_toggle(assigns) do
    assigns = assign(assigns, :next, if(assigns.look == "felt", do: "clean", else: "felt"))

    ~H"""
    <button
      class={["btn btn-sm btn-outline-secondary app-look-toggle", @look == "felt" && "active"]}
      aria-pressed={to_string(@look == "felt")}
      type="button"
      phx-click={
        JS.dispatch("ziwoas:set-look", detail: %{look: @next})
        |> JS.push("set_look", value: %{look: @next})
      }
    >
      Filz-Look
    </button>
    """
  end

  def time_zone do
    case Config.fetch() do
      {:ok, config} -> config.location.timezone
      {:error, _message} -> nil
    end
  end

  # A lamp's page lives under /lights but is reached from the Schalten tab.
  defp navigation(current_path) do
    items = [
      {~p"/", "Home", "nav_dashboard_plush.webp", []},
      {~p"/solakon", "PV", "nav_pv_plush.webp", []},
      {~p"/switches", "Schalten", "nav_switches_plush.webp", ["/lights"]},
      {~p"/reports", "Berichte", "nav_reports_plush.webp", []},
      {~p"/weather", "Wetter", "nav_weather_plush.webp", []},
      {~p"/sensors", "Sensoren", "nav_sensors_plush.webp", []}
    ]

    for {path, label, icon, sections} <- items do
      %{
        path: path,
        label: label,
        icon: icon,
        current: Enum.any?([path | sections], &current_section?(current_path, &1))
      }
    end
  end

  # Home's sub-page prefix would be "//", so Home is only ever active on itself.
  defp current_section?(current_path, path),
    do: current_path == path or String.starts_with?(current_path, path <> "/")
end
