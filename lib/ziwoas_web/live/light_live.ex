defmodule ZiwoasWeb.LightLive do
  @moduledoc """
  A lamp's page: power and zones, brightness, white, colour and scenes, and the
  settings gear. `{:light_updated, key}` from `Ziwoas.Lights.GoveeSubscriber`
  reloads the hero's snapshot alone, so the sliders keep what the hand is doing.

  Brightness, white and colour are the `LightDetail` hook's `"light_command"`
  events; power, zones, scenes and the toast's undo send the same event from
  their buttons (`ZiwoasWeb.LightEvents`). The gear opens the settings sheet in
  place.
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
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, "light_#{key}")

    {:ok,
     assign(socket,
       page_title: light.name,
       light: light,
       snapshot: snapshot,
       power_snapshot: snapshot,
       toast: %{message: nil, undo: nil},
       toast_timer: nil,
       settings: nil
     )}
  end

  @impl true
  def handle_info({:light_updated, _key}, socket), do: {:noreply, refresh_power(socket)}

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

      {:ok, _light, _sent} ->
        {:noreply, socket}

      {:error, :commander} ->
        {:noreply, put_flash(socket, :error, LightEvents.failed_message())}

      {:error, _reason} ->
        {:noreply, socket}
    end
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

  defp refresh_power(socket),
    do: assign(socket, :power_snapshot, Lights.snapshot(socket.assigns.light))

  defp show_toast(socket, toast) do
    if timer = socket.assigns.toast_timer, do: Process.cancel_timer(timer)
    assign(socket, toast: toast, toast_timer: Process.send_after(self(), :hide_toast, @toast_ms))
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        brightness: max(Lights.brightness(assigns.snapshot), 1),
        plugs: Config.get().plugs,
        tabs:
          [{"white", "Weiß"}] ++
            if(assigns.light.supports_color, do: [{"color", "Farbe"}], else: []) ++
            [{"scenes", "Szenen"}]
      )

    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <div id="light_detail" phx-hook="LightDetail" data-key={@light.key}>
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
          <.settings_sheet :if={@settings} form={@settings} plugs={@plugs} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
