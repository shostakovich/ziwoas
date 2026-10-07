defmodule ZiwoasWeb.Layouts do
  @moduledoc """
  The application shell, ported from `app/views/layouts/application.html.erb`:
  `root` (the document and its head) and `app/1` (header, navigation, main,
  tab bar). LiveViews wrap their markup in `<Layouts.app>`; controllers
  rendering HTML do the same in their templates.
  """
  use ZiwoasWeb, :html

  alias Ziwoas.{Config, Look}

  embed_templates "layouts/*"

  # A lamp's page lives under /lights but is reached from the Schalten tab.
  @navigation [
    {"/", "Home", "nav_dashboard_plush.webp", []},
    {"/solakon", "PV", "nav_pv_plush.webp", []},
    {"/switches", "Schalten", "nav_switches_plush.webp", ["/lights"]},
    {"/reports", "Berichte", "nav_reports_plush.webp", []},
    {"/weather", "Wetter", "nav_weather_plush.webp", []},
    {"/sensors", "Sensoren", "nav_sensors_plush.webp", []}
  ]

  attr :look, :string, required: true
  attr :current_path, :string, required: true
  attr :main_class, :any, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :navigation, navigation(assigns.current_path))

    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <div class="container pt-3">
      <header class="navbar navbar-expand px-3 app-header mb-3">
        <a
          class="navbar-brand app-brand d-flex align-items-center py-0"
          aria-label="Zipfelmaus — Startseite"
          href="/"
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
        </a>
        <nav class="d-none d-lg-block me-auto" aria-label="Hauptnavigation">
          <ul class="navbar-nav nav-pills flex-nowrap">
            <li :for={item <- @navigation} class="nav-item">
              <a
                class={["nav-link d-flex align-items-center gap-2 px-2", item.current && "active"]}
                aria-current={item.current && "page"}
                href={item.path}
              >
                <img alt="" class="app-nav-icon" aria-hidden="true" src={~p"/images/#{item.icon}"} />
                {item.label}
              </a>
            </li>
          </ul>
        </nav>
        <div class="d-flex align-items-center ms-auto">
          <.look_toggle look={@look} />
        </div>
      </header>
    </div>

    <main class={["container app-main", @main_class]} id="main">
      {render_slot(@inner_block)}
    </main>

    <nav class="navbar fixed-bottom pb-safe d-lg-none" aria-label="Tab-Leiste">
      <ul class="nav nav-pills nav-justified flex-nowrap w-100">
        <li :for={item <- @navigation} class="nav-item">
          <a
            class={["nav-link d-flex flex-column align-items-center", item.current && "active"]}
            aria-current={item.current && "page"}
            href={item.path}
          >
            <img alt="" class="app-nav-icon" aria-hidden="true" src={~p"/images/#{item.icon}"} />
            <small>{item.label}</small>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  attr :look, :string, required: true

  # A full page load: the look lives on <html>.
  defp look_toggle(assigns) do
    ~H"""
    <form class="button_to" method="post" action="/look">
      <input type="hidden" name="_method" value="patch" />
      <button
        class={["btn btn-sm btn-outline-secondary app-look-toggle", @look == "felt" && "active"]}
        aria-pressed={to_string(@look == "felt")}
        type="submit"
      >
        Filz-Look
      </button>
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="look" value={if @look == "felt", do: "clean", else: "felt"} />
    </form>
    """
  end

  @doc "The zone Rails exposes as `ziwoas-time-zone` (its `Time.zone`, from the config)."
  def time_zone, do: Config.app_config().location.timezone

  def theme_colors(look), do: Look.theme_colors(look)

  defp navigation(current_path) do
    for {path, label, icon, sections} <- @navigation do
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
