defmodule ZiwoasWeb.DeviceLive do
  @moduledoc """
  A plug's or a heater's own page, reached from its tile on Schalten: the switch, the room it
  stands in and its Schaltzeiten or Zeitfenster.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.SwitchesComponents

  alias Ziwoas.{Clock, Config, Heating, Lights, Plugs, Rooms, Switching}
  alias ZiwoasWeb.SwitchEvents

  defmodule NotFound do
    defexception message: "Gerät nicht gefunden", plug_status: 404
  end

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Plugs.subscribe()
      Heating.subscribe()
      Lights.subscribe()
    end

    {:ok,
     socket
     |> assign(editor: nil, pending: MapSet.new(), readings: Heating.readings())
     |> assign_device(socket.assigns.live_action, params)
     |> load()}
  end

  defp assign_device(socket, :plug, %{"id" => id}) do
    case Enum.find(Config.get().plugs, &(&1.switchable and &1.id == id)) do
      nil -> raise NotFound
      plug -> assign(socket, owner: {:plug, plug.id}, plug: plug, page_title: plug.name)
    end
  end

  defp assign_device(socket, :heater, %{"key" => key}) do
    case Heating.get_heater(key) do
      nil -> raise NotFound
      heater -> assign(socket, owner: {:heater, key}, page_title: heater.name)
    end
  end

  @impl true
  def handle_info({:live, _deltas}, socket), do: {:noreply, load(socket)}
  def handle_info({:updated, _key}, socket), do: {:noreply, load(socket)}
  def handle_info({:power_up_failed, _failure}, socket), do: {:noreply, socket}

  def handle_info({:heaters, readings}, socket),
    do: {:noreply, socket |> assign(readings: readings) |> load()}

  @impl true
  def handle_event("switch_plug", %{"state" => state} = params, socket)
      when state in ~w[on off] do
    if own(socket, params) == :ok,
      do: {:noreply, SwitchEvents.switch_plug(socket, socket.assigns.plug, state)},
      else: {:noreply, socket}
  end

  def handle_event("switch_heater", %{"heater_key" => key, "state" => state} = params, socket)
      when state in ~w[heat frost] do
    if own(socket, params) == :ok,
      do: {:noreply, SwitchEvents.switch_heater(socket, key, state)},
      else: {:noreply, socket}
  end

  def handle_event("heat_c", %{"heater_key" => key, "step" => step} = params, socket)
      when step in ~w[up down] do
    if own(socket, params) == :ok,
      do: {:noreply, SwitchEvents.step_heat_c(socket, key, step)},
      else: {:noreply, socket}
  end

  def handle_event("place", %{"place" => %{"room_id" => room_id}}, socket) do
    case place(socket.assigns, room_id) do
      {:ok, _placed} ->
        {:noreply, socket |> put_flash(:info, placed_message(room_id)) |> load()}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Diesen Raum gibt es nicht mehr.") |> load()}
    end
  end

  def handle_event("new_entry", %{"kind" => kind} = params, socket) do
    with :ok <- own(socket, params),
         {:ok, kind} <- kind(socket.assigns.owner, kind) do
      {:noreply,
       assign(socket, editor: editor(kind, nil, change(socket.assigns.owner, kind, nil, %{})))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_entry", %{"kind" => kind, "id" => id} = params, socket)
      when is_binary(id) do
    owner = socket.assigns.owner

    with :ok <- own(socket, params),
         {:ok, kind} <- kind(owner, kind),
         entry when not is_nil(entry) <- find(owner, kind, id) do
      {:noreply, assign(socket, editor: editor(kind, id, change(owner, kind, entry, %{})))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_editor", _params, socket), do: {:noreply, close_editor(socket)}

  def handle_event("validate_entry", params, %{assigns: %{editor: %{} = editor}} = socket) do
    owner = socket.assigns.owner

    changeset =
      owner
      |> change(editor.kind, stored(owner, editor), attrs(params, editor.kind))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, editor: %{editor | form: to_form(changeset)})}
  end

  def handle_event("save_entry", params, %{assigns: %{editor: %{} = editor}} = socket),
    do: {:noreply, save(socket, editor, params)}

  def handle_event("set_enabled", %{"kind" => kind, "id" => id} = params, socket)
      when is_binary(id) do
    owner = socket.assigns.owner

    with :ok <- own(socket, params),
         {:ok, kind} <- kind(owner, kind),
         entry when not is_nil(entry) <- find(owner, kind, id) do
      enable(owner, kind, entry, params["enabled"] == "true")
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_entry", %{"kind" => kind, "id" => id} = params, socket)
      when is_binary(id) do
    owner = socket.assigns.owner

    with :ok <- own(socket, params),
         {:ok, kind} <- kind(owner, kind),
         entry when not is_nil(entry) <- find(owner, kind, id) do
      remove(owner, kind, entry)
      {:noreply, socket |> put_flash(:info, "#{noun(kind)} gelöscht.") |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(name, result, socket) do
    case SwitchEvents.settle(socket, name, result) do
      {socket, :ok} -> {:noreply, load(socket)}
      {socket, {:error, message}} -> {:noreply, socket |> put_flash(:error, message) |> load()}
    end
  end

  defp place(%{owner: {:plug, id}}, room_id), do: Rooms.place_plug(id, room_id)

  defp place(%{owner: {:heater, _key}, heater_row: row}, room_id),
    do: Heating.put_room(row.heater, %{"room_id" => room_id})

  defp placed_message(""), do: "Ohne Raum gespeichert."

  defp placed_message(room_id) do
    case Rooms.get(room_id) do
      nil -> "Raum gespeichert."
      room -> "Steht jetzt unter #{room.name}."
    end
  end

  # An event from an older page about another device changes nothing here.
  defp own(%{assigns: %{owner: {:plug, id}}}, %{"plug_id" => id}), do: :ok
  defp own(%{assigns: %{owner: {:heater, key}}}, %{"heater_key" => key}), do: :ok
  defp own(_socket, _params), do: :error

  defp kind(_owner, "window"), do: {:ok, :window}
  defp kind({:plug, _plug_id}, _kind), do: {:ok, :rule}
  defp kind({:heater, _key}, _kind), do: :error

  defp attrs(params, kind) do
    case params[to_string(kind)] do
      %{} = attrs -> attrs
      _ -> %{}
    end
  end

  defp editor(kind, id, changeset), do: %{kind: kind, id: id, form: to_form(changeset)}

  defp stored(_owner, %{id: nil}), do: nil
  defp stored(owner, %{kind: kind, id: id}), do: find(owner, kind, id)

  defp find({:plug, plug_id}, :window, id), do: Switching.window(plug_id, id)
  defp find({:plug, plug_id}, :rule, id), do: Switching.single(plug_id, id)
  defp find({:heater, key}, :window, id), do: Heating.window(key, id)

  defp change({:plug, _plug_id}, :window, window, attrs),
    do: Switching.change_window(window, attrs)

  defp change({:plug, _plug_id}, :rule, rule, attrs), do: Switching.change_single(rule, attrs)
  defp change({:heater, _key}, :window, window, attrs), do: Heating.change_window(window, attrs)

  defp store({:plug, plug_id}, %{kind: :window, id: id}, _window, attrs),
    do: Switching.save_window(plug_id, attrs, id)

  defp store({:plug, plug_id}, %{kind: :rule}, rule, attrs),
    do: Switching.save_single(plug_id, attrs, rule)

  defp store({:heater, key}, %{kind: :window}, window, attrs),
    do: Heating.save_window(key, attrs, window)

  defp enable({:plug, plug_id}, :window, window, enabled),
    do: Switching.set_enabled(Switching.group(plug_id, window.group_id), enabled)

  defp enable({:plug, _plug_id}, :rule, rule, enabled), do: Switching.set_enabled([rule], enabled)

  defp enable({:heater, _key}, :window, window, enabled),
    do: Heating.set_window_enabled(window, enabled)

  defp remove({:plug, plug_id}, :window, window),
    do: Switching.delete_rules(Switching.group(plug_id, window.group_id))

  defp remove({:plug, _plug_id}, :rule, rule), do: Switching.delete_rules([rule])
  defp remove({:heater, _key}, :window, window), do: Heating.delete_window(window)

  defp save(socket, editor, params) do
    owner = socket.assigns.owner
    entry = stored(owner, editor)

    if editor.id && is_nil(entry) do
      socket |> close_editor() |> load()
    else
      case store(owner, editor, entry, attrs(params, editor.kind)) do
        {:ok, _saved} ->
          socket
          |> close_editor()
          |> put_flash(:info, "#{noun(editor.kind)} gespeichert.")
          |> load()

        {:error, changeset} ->
          socket |> clear_flash() |> assign(editor: %{editor | form: to_form(changeset)})
      end
    end
  end

  defp noun(:window), do: "Zeitfenster"
  defp noun(:rule), do: "Schaltzeit"

  defp close_editor(%{assigns: %{editor: nil}} = socket), do: socket

  defp close_editor(socket) do
    ids = focus_return(socket.assigns.owner, socket.assigns.editor)
    socket |> assign(editor: nil) |> push_event("focus_return", %{ids: ids})
  end

  @impl true
  def render(%{owner: {:plug, _id}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} resident={@resident} width={:narrow}>
      <.header back={~p"/switches"} back_label="Schalten">
        {@plug.name}
        <:badge :if={@offline}>
          <.badge tone={:warning}>Offline</.badge>
        </:badge>
      </.header>

      <div class="flex flex-col gap-8" id="device" phx-hook="FocusReturn">
        <.card id="device_state" as="section">
          <div class="flex items-center gap-4">
            <.knob
              on={@lit}
              plush={if @lit, do: "shelly-plug", else: "shelly-plug-off"}
              label={@plug.name}
              disabled={@offline}
              busy={MapSet.member?(@pending, {:switch, @plug.id})}
              phx-click="switch_plug"
              phx-value-plug_id={@plug.id}
              phx-value-state={if @on, do: "off", else: "on"}
            />
            <div class="min-w-0">
              <p class="text-lg font-semibold tabular-nums" data-headline>
                {plug_headline(@row, @offline, @lit)}
              </p>
              <p class="text-sm text-base-content/70" data-status>{status_line(@row, @zone)}</p>
            </div>
          </div>
          <p :if={@lamps != []} class="mt-4 text-sm text-base-content/70" data-lamps>
            Hängt an dieser Steckdose:
            <span :for={{light, comma} <- @lamp_links} class="whitespace-nowrap">
              <.link navigate={~p"/lights/#{light.key}"} class="link">{light.name}</.link>{comma}
            </span>
          </p>
        </.card>

        <.room_section form={@room_form} rooms={@rooms} />

        <section id="device_schedule" aria-labelledby="device_schedule_heading">
          <.section_heading id="device_schedule_heading">Schaltzeiten</.section_heading>
          <.entries owner={@owner} entries={@row.entries} editor={@editor} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  def render(%{owner: {:heater, _key}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} resident={@resident} width={:narrow}>
      <.header back={~p"/switches"} back_label="Schalten">
        {@heater_row.heater.name}
        <:badge :if={@heater_offline}>
          <.badge tone={:warning}>Offline</.badge>
        </:badge>
      </.header>

      <div class="flex flex-col gap-8" id="device" phx-hook="FocusReturn">
        <.card id="device_state" as="section">
          <.heater_body
            row={@heater_row}
            zone={@zone}
            pending={MapSet.member?(@pending, {:switch_heater, @heater_row.heater.key})}
            heat_pending={MapSet.member?(@pending, {:heat_c, @heater_row.heater.key})}
          />
        </.card>

        <.room_section form={@room_form} rooms={@rooms} />

        <section id="device_schedule" aria-labelledby="device_schedule_heading">
          <.section_heading id="device_schedule_heading">Zeitfenster</.section_heading>
          <.entries owner={@owner} singles={false} entries={@heater_row.entries} editor={@editor} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :rooms, :list, required: true

  defp room_section(assigns) do
    ~H"""
    <section id="device_room" aria-labelledby="device_room_heading">
      <.section_heading id="device_room_heading">Raum</.section_heading>
      <.form for={@form} id="room_form" phx-change="place" phx-auto-recover="ignore">
        <.input
          field={@form[:room_id]}
          type="select"
          label="Steht unter"
          options={Enum.map(@rooms, &{&1.name, &1.id})}
          prompt="Ohne Raum"
          help={
            if @rooms == [],
              do: "Noch keine Räume. Lege sie unter Schalten › Räume an.",
              else: "Bestimmt, unter welchem Raum das Gerät auf Schalten steht."
          }
        />
      </.form>
    </section>
    """
  end

  defp plug_headline(_row, true, _lit), do: "Nicht erreichbar"
  defp plug_headline(row, false, true), do: "An · #{number(row.watt || 0, unit: "W")}"
  defp plug_headline(_row, false, false), do: "Aus"

  defp load(%{assigns: %{owner: {:plug, id}}} = socket) do
    zone = Config.get().location.timezone
    [row] = Switching.rows([socket.assigns.plug], Clock.now(), zone)
    on = Switching.Row.on?(row)
    offline = Switching.Row.offline?(row)
    lamps = Enum.filter(Lights.lights(), &(&1.shelly_plug_id == id))

    socket
    |> assign(zone: zone, row: row, on: on, offline: offline, lit: Switching.Row.lit?(row))
    |> assign(lamps: lamps, lamp_links: with_commas(lamps))
    |> assign_room(Rooms.plug_room(id))
  end

  defp load(%{assigns: %{owner: {:heater, key}}} = socket) do
    zone = Config.get().location.timezone

    case Enum.find(
           Heating.rows(socket.assigns.readings, Clock.now(), zone),
           &(&1.heater.key == key)
         ) do
      nil ->
        socket
        |> put_flash(:error, "Diese Heizung gibt es nicht mehr.")
        |> push_navigate(to: ~p"/switches")

      row ->
        socket
        |> assign(zone: zone, heater_row: row, heater_offline: Heating.Row.offline?(row))
        |> assign_room(row.heater.room_id)
    end
  end

  defp with_commas(lamps) do
    last = length(lamps)
    for {light, index} <- Enum.with_index(lamps, 1), do: {light, if(index < last, do: ",")}
  end

  defp assign_room(socket, room_id),
    do:
      assign(socket,
        rooms: Rooms.list(),
        room_form: to_form(%{"room_id" => room_id && to_string(room_id)}, as: :place)
      )
end
