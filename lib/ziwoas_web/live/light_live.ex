defmodule ZiwoasWeb.LightLive do
  @moduledoc """
  A lamp's page (Rails' `LightsController#show`): power and zones, brightness,
  white, colour and scenes, and the settings gear. Rails replaces only the power
  hero over its `light_<key>` stream; here `{:light_updated, key}` from
  `Ziwoas.Lights.GoveeSubscriber` reloads the hero's snapshot alone, so the sliders
  keep what the hand is doing.

  Brightness, white and colour are the `LightDetail` hook's `"light_command"`
  events; the forms — power, zones, scenes, the toast's undo — submit the same
  event (`ZiwoasWeb.LightEvents`), which redraws the hero and the toast as Rails'
  streams do. The gear opens the settings sheet in place (`"open_settings"`) and
  saves it through `Ziwoas.Lights.update_settings/2` (`light_settings`).
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents

  alias Ziwoas.{Config, Lights, Ownership}
  alias Ziwoas.Lights.Light
  alias ZiwoasWeb.LightEvents

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    light = Lights.get_by_key(key) || raise ZiwoasWeb.NotFoundError
    snapshot = Lights.snapshot(light)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, "light_#{key}")

    {:ok,
     assign(socket,
       page_title: light.name,
       light: light,
       snapshot: snapshot,
       power_snapshot: snapshot,
       toast: %{message: nil, undo: nil},
       settings: nil
     )}
  end

  @impl true
  def handle_info({:light_updated, _key}, socket),
    do: {:noreply, assign(socket, :power_snapshot, Lights.snapshot(socket.assigns.light))}

  def handle_info(:hide_toast, socket),
    do: {:noreply, assign(socket, toast: %{message: nil, undo: nil}, toast_timer: nil)}

  @impl true
  def handle_event("light_command", params, socket) do
    case LightEvents.run(params) do
      {:ok, light, {:zones, _keys, toast}} ->
        socket = assign(socket, :power_snapshot, Lights.snapshot(socket.assigns.light))
        {:noreply, if(toast, do: show_toast(socket, toast_assigns(light, toast)), else: socket)}

      {:ok, _light, :power} ->
        {:noreply, assign(socket, :power_snapshot, Lights.snapshot(socket.assigns.light))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_settings", _params, socket),
    do: {:noreply, assign(socket, :settings, settings(socket.assigns.light, []))}

  def handle_event("close_settings", _params, socket),
    do: {:noreply, assign(socket, :settings, nil)}

  def handle_event("save_settings", params, socket) do
    attrs = Map.take(Map.get(params, "light", %{}), ~w[name shelly_plug_id])

    if Ownership.owner?(:light_settings) do
      case Lights.update_settings(socket.assigns.light, attrs) do
        {:ok, light} ->
          {:noreply, assign(socket, light: light, page_title: light.name, settings: nil)}

        {:error, changeset} ->
          light = Ecto.Changeset.apply_changes(changeset)
          {:noreply, assign(socket, :settings, settings(light, Light.full_messages(changeset)))}
      end
    else
      {:noreply, socket}
    end
  end

  defp settings(light, errors),
    do: %{light: light, plugs: Config.app_config().plugs, errors: errors}

  # The toast hides itself after 5 s, as Rails' toast controller hid it in the browser.
  @toast_ms 5_000

  defp show_toast(socket, toast) do
    if timer = socket.assigns[:toast_timer], do: Process.cancel_timer(timer)
    assign(socket, toast: toast, toast_timer: Process.send_after(self(), :hide_toast, @toast_ms))
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        brightness: max(Lights.brightness(assigns.snapshot), 1),
        tabs:
          [{"white", "Weiß"}] ++
            if(assigns.light.supports_color, do: [{"color", "Farbe"}], else: []) ++
            [{"scenes", "Szenen"}]
      )

    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <div id="light_detail" phx-hook="LightDetail" data-key={@light.key}>
        <div class="d-flex align-items-center gap-2 mb-3">
          <a class="btn btn-icon btn-light flex-shrink-0" aria-label="Zurück" href="/switches">←</a>
          <h1 class="ld-title h2 mb-0 me-auto">{@light.name}</h1>
          <a
            class="btn btn-icon flex-shrink-0"
            data-turbo-stream="true"
            aria-label="Einstellungen"
            href={"/lights/#{@light.key}/edit"}
            phx-click="open_settings"
          >
            <img
              width="28"
              height="28"
              alt=""
              aria-hidden="true"
              src={~p"/images/settings_plush.webp"}
            />
          </a>
        </div>

        <.power snapshot={@power_snapshot} />

        <div class="card mb-3">
          <div class="card-body">
            <div class="d-flex gap-1 mb-2 small text-uppercase text-body-secondary">
              <label for="light_brightness">Helligkeit</label><span aria-hidden="true">·</span>
              <output
                for="light_brightness"
                class="text-body tabular-nums"
                data-light="brightness-value"
              >{@brightness} %</output>
            </div>
            <input
              class="form-range ld-range"
              type="range"
              id="light_brightness"
              phx-update="ignore"
              min="1"
              max="100"
              value={@brightness}
              data-light="brightness"
            />
          </div>
        </div>

        <div class="nav nav-pills nav-fill mb-3" role="tablist" aria-label="Lichtart">
          <button
            :for={{key, label} <- @tabs}
            type="button"
            class="nav-link"
            role="tab"
            id={"light_tab_#{key}"}
            phx-update="ignore"
            aria-controls={"light_panel_#{key}"}
            aria-selected="false"
            data-tab={key}
          >
            {label}
          </button>
        </div>

        <.white_panel snapshot={@snapshot} />
        <.color_panel :if={@light.supports_color} snapshot={@snapshot} />
        <.scenes light={@light} />

        <div class="toast-container ld-toast-container">
          <.toast message={@toast.message} undo={@toast.undo} />
        </div>

        <div id="light_settings">
          <.settings_sheet
            :if={@settings}
            light={@settings.light}
            plugs={@settings.plugs}
            errors={@settings.errors}
            live
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
