defmodule ZiwoasWeb.LightLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents

  alias Ziwoas.{Lights, Plugs}
  alias ZiwoasWeb.LightEvents

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    light = Lights.get_by_key!(key)
    snapshot = Lights.snapshot(light)

    if connected?(socket) do
      Lights.subscribe(key)
      Plugs.subscribe()
    end

    {:ok,
     socket
     |> assign(lamp_values(snapshot))
     |> assign(
       page_title: light.name,
       light: light,
       plugs: Lights.lamp_plugs(),
       tabs: tabs_of(light),
       tab: "white",
       power_snapshot: snapshot,
       revert: nil,
       toast: toast_assigns(light, :clear),
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

  def handle_info({:live, deltas}, socket) do
    if Lights.power_changed?(socket.assigns.power_snapshot, deltas),
      do: {:noreply, refresh_power(socket)},
      else: {:noreply, socket}
  end

  def handle_info({:power_up_failed, {_key, failure}}, socket) do
    message = LightEvents.power_up_failed_message(socket.assigns.light.name, failure)
    {:noreply, socket |> put_flash(:error, message) |> refresh_power()}
  end

  @impl true
  def handle_event("light_command", %{"command" => command} = params, socket) do
    if Lights.command?(command) do
      params = Map.put(params, "light_key", socket.assigns.light.key)

      {:noreply,
       socket
       |> hide_toast()
       |> start_async({:light_command, command}, fn -> LightEvents.run(params) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("light_command", _params, socket), do: {:noreply, socket}

  def handle_event("hide_toast", _params, socket), do: {:noreply, hide_toast(socket)}

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
         |> refresh_power()
         |> put_flash(:info, "Lampe aktualisiert.")}

      {:error, changeset} ->
        {:noreply, socket |> clear_flash() |> assign(:settings, to_form(changeset))}
    end
  end

  @impl true
  def handle_async({:light_command, _command}, {:ok, result}, socket) do
    case result do
      {:ok, light, {:zones, _keys, toast}} ->
        socket = refresh_power(socket)

        {:noreply,
         if(toast, do: assign(socket, :toast, toast_assigns(light, toast)), else: socket)}

      {:ok, _light, :power} ->
        {:noreply, refresh_power(socket)}

      {:ok, _light, {:starting, verb}} ->
        {:noreply, socket |> refresh_power() |> keep(verb)}

      {:ok, _light, {:sent, verb}} ->
        {:noreply, socket |> assign(:revert, nil) |> keep(verb)}

      {:error, :unreachable} ->
        {:noreply, failed(socket)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_async({:light_command, _command}, {:exit, _reason}, socket),
    do: {:noreply, failed(socket)}

  # The thumbs and swatches moved on the client; a new `revert` sends them back.
  defp failed(socket) do
    socket
    |> put_flash(:error, LightEvents.failed_message())
    |> update(:revert, &((&1 || 0) + 1))
  end

  defp keep(socket, {:brightness, value}), do: assign(socket, :brightness, value)
  defp keep(socket, {:color_temp, kelvin}), do: assign(socket, kelvin: kelvin, color: nil)
  defp keep(socket, {:color, rgb}), do: assign(socket, color: hex(rgb), kelvin: nil)
  defp keep(socket, _verb), do: socket

  # Only what the lamp reported anew moves the controls, so a value just set stays until then.
  defp refresh_power(socket) do
    snapshot = Lights.snapshot(socket.assigns.light)
    known = lamp_values(socket.assigns.power_snapshot)
    reported = snapshot |> lamp_values() |> Map.reject(fn {key, value} -> known[key] == value end)

    socket |> assign(:power_snapshot, snapshot) |> assign(reported)
  end

  defp lamp_values(snapshot) do
    kelvin = Lights.color_temp_k(snapshot)

    %{
      brightness: max(Lights.brightness(snapshot), 1),
      kelvin: if(kelvin && kelvin > 0, do: kelvin),
      color: if(not Lights.white?(snapshot), do: color_hex(snapshot))
    }
  end

  defp hide_toast(socket), do: assign(socket, :toast, toast_assigns(socket.assigns.light, :clear))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <div id="light_detail" data-key={@light.key}>
        <.header back={~p"/switches"}>
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

        <.starting_notice snapshot={@power_snapshot} />
        <.power snapshot={@power_snapshot} />
        <.brightness_panel brightness={@brightness} revert={@revert} />
        <.light_tabs tabs={@tabs} active={@tab} />

        <.white_panel light={@light} kelvin={@kelvin} revert={@revert} hidden={@tab != "white"} />
        <.color_panel
          :if={@light.supports_color}
          color={@color}
          revert={@revert}
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
