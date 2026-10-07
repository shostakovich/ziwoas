defmodule ZiwoasWeb.LightLive do
  @moduledoc """
  A lamp's page: power and zones, brightness, white, colour and scenes, and the
  settings gear. `Ziwoas.Lights`' update for the lamp reloads the hero's
  snapshot alone, so the controls keep what the hand is doing.

  Every control sends `"light_command"` (`ZiwoasWeb.LightEvents`): the
  brightness and white sliders as forms debounced by `phx-debounce`, the buttons
  and swatches by `phx-click`, the colour wheel through the `LightDetail` hook.
  What a command set is kept in assigns (`brightness`, `kelvin`, `color`); the
  tabs are an assign too. The gear opens the settings sheet in place.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents

  alias Ziwoas.{Config, Lights}
  alias ZiwoasWeb.LightEvents

  # The toast hides itself after 5 s.
  @toast_ms 5_000

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    light = Lights.get_by_key!(key)
    snapshot = Lights.snapshot(light)
    if connected?(socket), do: Lights.subscribe(key)

    {:ok,
     assign(socket,
       page_title: light.name,
       light: light,
       plugs: Config.get().plugs,
       tabs: tabs_of(light),
       tab: "white",
       power_snapshot: snapshot,
       brightness: max(Lights.brightness(snapshot), 1),
       kelvin: Lights.color_temp_k(snapshot),
       color: if(Lights.white?(snapshot), do: nil, else: color_hex(snapshot)),
       toast: %{message: nil, undo: nil},
       toast_timer: nil,
       settings: nil
     )}
  end

  defp tabs_of(light) do
    [{"white", "Weiß"}] ++
      if(light.supports_color, do: [{"color", "Farbe"}], else: []) ++
      [{"scenes", "Szenen"}]
  end

  @impl true
  def handle_info({:updated, _key}, socket), do: {:noreply, refresh_power(socket)}

  def handle_info(:hide_toast, socket),
    do: {:noreply, assign(socket, toast: %{message: nil, undo: nil}, toast_timer: nil)}

  @impl true
  def handle_event("light_command", params, socket) do
    params = Map.put(params, "light_key", socket.assigns.light.key)

    case LightEvents.run(params) do
      {:ok, light, {:zones, _keys, toast}} ->
        socket = refresh_power(socket)
        {:noreply, if(toast, do: show_toast(socket, toast_assigns(light, toast)), else: socket)}

      {:ok, _light, :power} ->
        {:noreply, refresh_power(socket)}

      {:ok, _light, {:sent, verb}} ->
        {:noreply, keep(socket, verb)}

      {:error, :unreachable} ->
        {:noreply, put_flash(socket, :error, LightEvents.failed_message())}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    if List.keymember?(socket.assigns.tabs, tab, 0),
      do: {:noreply, assign(socket, :tab, tab)},
      else: {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket),
    do:
      {:noreply, assign(socket, :settings, to_form(Lights.change_settings(socket.assigns.light)))}

  def handle_event("close_settings", _params, socket),
    do: {:noreply, assign(socket, :settings, nil)}

  def handle_event("validate_settings", %{"light" => params}, socket) do
    changeset =
      socket.assigns.light |> Lights.change_settings(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :settings, to_form(changeset))}
  end

  def handle_event("save_settings", %{"light" => params}, socket) do
    case Lights.update_settings(socket.assigns.light, params) do
      {:ok, light} ->
        {:noreply,
         socket
         |> assign(light: light, page_title: light.name, settings: nil)
         |> put_flash(:info, "Lampe aktualisiert.")}

      {:error, changeset} ->
        {:noreply, socket |> clear_flash() |> assign(:settings, to_form(changeset))}
    end
  end

  # What the hand set stays on the controls; the lamp's report only redraws the hero.
  defp keep(socket, {:brightness, value}), do: assign(socket, :brightness, value)
  defp keep(socket, {:color_temp, kelvin}), do: assign(socket, :kelvin, kelvin)
  defp keep(socket, {:color, rgb}), do: assign(socket, :color, hex(rgb))
  defp keep(socket, _verb), do: socket

  defp refresh_power(socket),
    do: assign(socket, :power_snapshot, Lights.snapshot(socket.assigns.light))

  defp show_toast(socket, toast) do
    if timer = socket.assigns.toast_timer, do: Process.cancel_timer(timer)
    assign(socket, toast: toast, toast_timer: Process.send_after(self(), :hide_toast, @toast_ms))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <div id="light_detail" data-key={@light.key}>
        <.header title_class="ld-title">
          <:leading>
            <.link
              class="btn btn-icon btn-light flex-shrink-0"
              aria-label="Zurück"
              navigate={~p"/switches"}
            >
              ←
            </.link>
          </:leading>
          {@light.name}
          <:actions>
            <button
              type="button"
              class="btn btn-icon flex-shrink-0"
              aria-label="Einstellungen"
              phx-click="open_settings"
            >
              <img
                width="28"
                height="28"
                alt=""
                aria-hidden="true"
                src={~p"/images/settings_plush.webp"}
              />
            </button>
          </:actions>
        </.header>

        <.power snapshot={@power_snapshot} />
        <.brightness_panel brightness={@brightness} />
        <.tabs tabs={@tabs} active={@tab} />

        <.white_panel light={@light} kelvin={@kelvin} hidden={@tab != "white"} />
        <.color_panel
          :if={@light.supports_color}
          color={@color}
          zone_lamp={Lights.zone_lamp?(@power_snapshot)}
          hidden={@tab != "color"}
        />
        <.scenes light={@light} hidden={@tab != "scenes"} />

        <div class="toast-container ld-toast-container">
          <.toast message={@toast.message} undo={@toast.undo} />
        </div>

        <div id="light_settings">
          <.settings_sheet :if={@settings} form={@settings} plugs={@plugs} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
