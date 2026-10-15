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

    values = lamp_values(snapshot)

    {:ok,
     socket
     |> assign(values)
     |> assign(
       page_title: light.name,
       light: light,
       plugs: Lights.lamp_plugs(),
       panels: panels_of(light),
       panel: if(values.color && light.supports_color, do: "color", else: "white"),
       power_snapshot: snapshot,
       revert: nil,
       toast: toast_assigns(light, :clear),
       settings: nil,
       settings_open: false
     )}
  end

  defp panels_of(light) do
    [{"Weiß", "white"}] ++
      if(light.supports_color, do: [{"Farbe", "color"}], else: []) ++
      [{"Szenen", "scenes"}]
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
  def handle_event("light_command", params, socket), do: {:noreply, command(socket, params)}

  def handle_event("turn", %{"value" => on}, socket),
    do: {:noreply, command(socket, %{"command" => "turn", "on" => on})}

  def handle_event("color_temp_preset", %{"value" => kelvin}, socket),
    do: {:noreply, command(socket, %{"command" => "color_temp", "temp_k" => kelvin})}

  def handle_event("hide_toast", _params, socket), do: {:noreply, hide_toast(socket)}

  def handle_event("show_panel", %{"value" => panel}, socket) do
    if List.keymember?(socket.assigns.panels, panel, 1),
      do: {:noreply, assign(socket, :panel, panel)},
      else: {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket) do
    form = to_form(Lights.change_settings(socket.assigns.light))
    {:noreply, assign(socket, settings: form, settings_open: true)}
  end

  def handle_event("close_settings", _params, socket),
    do: {:noreply, assign(socket, :settings_open, false)}

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
         |> assign(light: light, page_title: light.name, settings_open: false)
         |> refresh_power()
         |> put_flash(:info, "Lampe aktualisiert.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(:settings, to_form(changeset))}
    end
  end

  defp command(socket, %{"command" => command} = params) do
    if Lights.command?(command) do
      params = Map.put(params, "light_key", socket.assigns.light.key)

      socket
      |> hide_toast()
      |> start_async({:light_command, command}, fn -> LightEvents.run(params) end)
    else
      socket
    end
  end

  defp command(socket, _params), do: socket

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
        <.header back={~p"/switches"} back_label="Schalten">
          {@light.name}
          <:actions>
            <button
              type="button"
              id="light_settings_open"
              class="btn btn-square"
              aria-label="Einstellungen"
              aria-haspopup="dialog"
              phx-click="open_settings"
            >
              <.plush name="settings" size={:md} />
            </button>
          </:actions>
        </.header>
        <.starting_notice snapshot={@power_snapshot} class="mb-6" />

        <div class="flex flex-col gap-8">
          <.power snapshot={@power_snapshot} />
          <.brightness_panel
            brightness={@brightness}
            on={Lights.lit?(@power_snapshot)}
            revert={@revert}
          />

          <.light_panels panels={@panels} active={@panel}>
            <.white_panel
              light={@light}
              kelvin={@kelvin}
              revert={@revert}
              hidden={@panel != "white"}
            />
            <.color_panel
              :if={@light.supports_color}
              color={@color}
              revert={@revert}
              zone_lamp={Lights.zone_lamp?(@power_snapshot)}
              hidden={@panel != "color"}
            />
            <.scenes light={@light} hidden={@panel != "scenes"} />
          </.light_panels>
        </div>

        <.toast message={@toast.message} undo={@toast.undo} />
        <.settings_sheet form={@settings} open={@settings_open} plugs={@plugs} />
      </div>
    </Layouts.app>
    """
  end
end
