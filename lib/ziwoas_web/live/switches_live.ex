defmodule ZiwoasWeb.SwitchesLive do
  @moduledoc """
  Schalten: every lamp, heater and switchable plug, grouped by room (ADR-0014). On top a
  summary per kind that filters the page to it, then a bar of room chips that jumps to a room.
  A tile switches its device; its name opens the device's page with the schedule.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents
  import ZiwoasWeb.SwitchesComponents

  alias Ziwoas.{Clock, Config, Heating, Lights, Plugs, Rooms, Sensors, Switching}
  alias ZiwoasWeb.{LightEvents, RoomAirComponents, SwitchEvents}

  @filters %{"lampen" => :lamp, "heizungen" => :heater, "steckdosen" => :plug}
  @filter_params Map.new(@filters, fn {param, kind} -> {kind, param} end)
  @filter_names %{lamp: "Lampen", heater: "Heizungen", plug: "Steckdosen"}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Plugs.subscribe()
      Lights.subscribe()
      Heating.subscribe()
      Sensors.subscribe()
    end

    {:ok,
     socket
     |> assign(page_title: "Schalten", tick: nil, pending: MapSet.new(), filter: nil)
     |> assign(readings: Heating.readings())
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, socket |> assign(filter: @filters[params["nur"]]) |> assign_sections()}

  @impl true
  def handle_info({:live, _deltas}, socket), do: {:noreply, load(socket)}

  def handle_info({:updated, _key}, socket), do: {:noreply, load_lights(socket)}

  def handle_info({:heaters, readings}, socket),
    do: {:noreply, socket |> assign(readings: readings) |> load()}

  def handle_info({:reading, _reading}, socket) do
    air = room_air(Config.get(), socket.assigns.rooms, Clock.now())
    {:noreply, socket |> assign(air: air) |> assign_sections()}
  end

  def handle_info({:polled, _instant}, socket), do: {:noreply, socket}

  def handle_info({:power_up_failed, {key, failure}}, socket) do
    name = Enum.find_value(socket.assigns.snapshots, key, &(&1.light.key == key && &1.light.name))
    message = LightEvents.power_up_failed_message(name, failure)
    {:noreply, socket |> put_flash(:error, message) |> load_lights()}
  end

  def handle_info(:tick, socket),
    do: {:noreply, socket |> assign(now: Clock.now(), tick: nil) |> tick_while_starting()}

  @impl true
  def handle_event("switch_heater", %{"heater_key" => key, "state" => state}, socket)
      when state in ~w[heat frost] do
    if heater(socket, key),
      do: {:noreply, SwitchEvents.switch_heater(socket, key, state)},
      else: {:noreply, socket}
  end

  def handle_event("heat_c", %{"heater_key" => key, "step" => step}, socket)
      when step in ~w[up down] do
    if heater(socket, key),
      do: {:noreply, SwitchEvents.step_heat_c(socket, key, step)},
      else: {:noreply, socket}
  end

  def handle_event("switch_plug", %{"plug_id" => plug_id, "state" => state}, socket)
      when state in ~w[on off] do
    case plug(socket, plug_id) do
      nil -> {:noreply, socket}
      plug -> {:noreply, SwitchEvents.switch_plug(socket, plug, state)}
    end
  end

  def handle_event("light_command", %{"light_key" => key} = params, socket),
    do: {:noreply, light_command(socket, key, params)}

  def handle_event("lamps_off", %{"room" => room}, socket) do
    known = MapSet.new(socket.assigns.rooms, & &1.id)

    socket =
      socket.assigns.snapshots
      |> Enum.filter(&(Lights.lit?(&1) and in_scope?(&1.light.room_id, room, known)))
      |> Enum.reduce(socket, fn %{light: %{key: key}}, socket ->
        light_command(socket, key, %{"light_key" => key, "command" => "turn", "on" => "false"})
      end)

    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp light_command(socket, key, params),
    do: SwitchEvents.start(socket, {:light_command, key}, fn -> LightEvents.run(params) end)

  defp in_scope?(_room_id, "all", _known), do: true
  defp in_scope?(room_id, "none", known), do: not MapSet.member?(known, room_id)
  defp in_scope?(room_id, room, _known), do: to_string(room_id) == room

  @impl true
  def handle_async({:light_command, _key} = name, result, socket) do
    socket = update(socket, :pending, &MapSet.delete(&1, name))

    case result do
      {:ok, {:ok, _light, _result}} -> {:noreply, load_lights(socket)}
      {:ok, {:error, reason}} when reason in [:not_found, :invalid] -> {:noreply, socket}
      _unreachable -> {:noreply, put_flash(socket, :error, LightEvents.failed_message())}
    end
  end

  def handle_async(name, result, socket) do
    case SwitchEvents.settle(socket, name, result) do
      {socket, :ok} ->
        {:noreply, load(socket)}

      {socket, {:error, message}} ->
        {:noreply,
         socket |> put_flash(:error, "#{device_name(socket, name)}: #{message}") |> load()}
    end
  end

  defp device_name(socket, {:switch, plug_id}),
    do: Enum.find_value(socket.assigns.rows, plug_id, &(&1.plug.id == plug_id && &1.plug.name))

  defp device_name(socket, {_kind, key}),
    do:
      Enum.find_value(
        socket.assigns.heater_rows,
        key,
        &(&1.heater.key == key && &1.heater.name)
      )

  defp plug(socket, plug_id),
    do: Enum.find_value(socket.assigns.rows, &(&1.plug.id == plug_id && &1.plug))

  defp heater(socket, key),
    do: Enum.find_value(socket.assigns.heater_rows, &(&1.heater.key == key && &1.heater))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:default}>
      <.header>
        Schalten
        <:actions>
          <.button
            id="sw_rooms_link"
            navigate={~p"/switches/rooms"}
            size={:sm}
            variant={:ghost}
            icon="house"
          >
            Räume
          </.button>
        </:actions>
      </.header>

      <.empty_state :if={@nothing?} plush="plug" title="Noch nichts zu schalten">
        Lampen und Heizungen erscheinen, sobald ZiWoAS sie findet. Steckdosen markierst du in
        <code>ziwoas.yml</code>
        mit <code>switchable: true</code>.
      </.empty_state>

      <div :if={not @nothing?}>
        <nav id="sw_summary" aria-label="Geräte nach Art" class="sw-summaries">
          <.summary
            :for={summary <- @summaries}
            kind={summary.kind}
            plush={summary.plush}
            label={summary.label}
            text={summary.text}
            current={@shown_filter == summary.kind}
          />
        </nav>

        <div :if={@shown_filter} id="sw_filter" class="sw-filter">
          <span>Nur {@filter_name}, alle Räume</span>
          <div class="flex flex-wrap justify-end gap-2">
            <.button
              :if={@shown_filter == :lamp and @any_lamp_lit}
              id="sw_all_lamps_off"
              size={:sm}
              icon="power"
              phx-click="lamps_off"
              phx-value-room="all"
            >
              Alle Lampen aus
            </.button>
            <.button patch={~p"/switches"} size={:sm} variant={:ghost} icon="x">
              Alle zeigen
            </.button>
          </div>
        </div>

        <nav
          :if={@sections != []}
          id="sw_rooms_nav"
          aria-label="Räume"
          class="sw-room-nav"
          phx-hook="RoomNav"
        >
          <a
            :for={section <- @sections}
            href={"##{section.id}"}
            class="sw-room-chip"
            data-room={section.id}
          >
            <span
              class={["sw-room-dot", section.on_count > 0 && "sw-room-dot-on"]}
              aria-hidden="true"
            ></span>{section.name}
          </a>
        </nav>

        <section
          :for={section <- @sections}
          id={section.id}
          class="sw-room"
          aria-labelledby={"#{section.id}_heading"}
        >
          <div class="sw-room-head">
            <div class="min-w-0">
              <h2 id={"#{section.id}_heading"} class="sw-room-title">
                {section.name}
                <span class="font-normal text-base-content/70 tabular-nums" data-on-count>
                  {if section.on_count > 0, do: "#{section.on_count} an", else: "alles aus"}
                </span>
              </h2>
              <.room_air :if={section.air} air={section.air} />
              <p :if={is_nil(section.room)} class="text-sm text-base-content/70">
                Neu erkannte Geräte landen hier. Den Raum wählst du auf der Seite des Geräts.
              </p>
            </div>
            <.button
              :if={section.lamp_lit}
              id={"#{section.id}_lamps_off"}
              size={:sm}
              icon="power"
              phx-click="lamps_off"
              phx-value-room={(section.room && section.room.id) || "none"}
            >
              Lampen aus
            </.button>
          </div>
          <div class="sw-tiles">
            <.heater_tile
              :for={row <- section.heaters}
              row={row}
              zone={@zone}
              pending={MapSet.member?(@pending, {:switch_heater, row.heater.key})}
              heat_pending={MapSet.member?(@pending, {:heat_c, row.heater.key})}
            />
            <.lamp_tile
              :for={snapshot <- section.lamps}
              snapshot={snapshot}
              now={@now}
              pending={MapSet.member?(@pending, {:light_command, snapshot.light.key})}
            />
            <.plug_tile
              :for={row <- section.plugs}
              row={row}
              zone={@zone}
              pending={MapSet.member?(@pending, {:switch, row.plug.id})}
            />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :kind, :atom, required: true
  attr :plush, :string, required: true
  attr :label, :string, required: true
  attr :text, :string, required: true
  attr :current, :boolean, required: true

  defp summary(assigns) do
    assigns = assign(assigns, :param, @filter_params[assigns.kind])

    ~H"""
    <.link
      id={"sw_summary_#{@param}"}
      patch={if @current, do: ~p"/switches", else: ~p"/switches?#{[nur: @param]}"}
      class="sw-summary"
      aria-current={@current && "true"}
    >
      <.plush name={@plush} class="sw-summary-plush" />
      <span class="min-w-0">
        <span class="sw-summary-label">{@label}</span>
        <span class="sw-summary-text" data-summary>{@text}</span>
      </span>
    </.link>
    """
  end

  attr :air, :map, required: true

  defp room_air(assigns) do
    values = assigns.air.reading.values
    temperature = values[:temperature]
    co2 = values[:co2]

    assigns =
      assign(assigns,
        parts:
          Enum.reject(
            [
              temperature && number(temperature.value, precision: 1, unit: "°C"),
              co2 && "CO₂ #{number(co2.value, unit: "ppm")}"
            ],
            &is_nil/1
          ),
        level: assigns.air.verdict && elem(assigns.air.verdict, 0)
      )

    ~H"""
    <p
      class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-base-content/70 tabular-nums"
      data-air
    >
      <.link :if={@parts != []} navigate={~p"/sensors"} class="hover:underline">
        {join_meta(@parts)}
      </.link>
      <.badge :if={@level == :warn} tone={:warning}>
        {RoomAirComponents.verdict_word(@air.verdict)}
      </.badge>
      <.badge :if={@level == :bad} tone={:error} style={:solid}>
        {RoomAirComponents.verdict_word(@air.verdict)}
      </.badge>
    </p>
    """
  end

  defp load(socket) do
    config = Config.get()
    zone = config.location.timezone
    now = Clock.now()
    plugs = Enum.filter(config.plugs, & &1.switchable)
    rooms = Rooms.list()

    socket
    |> assign(
      zone: zone,
      rooms: rooms,
      plug_rooms: Rooms.plug_rooms(),
      rows: Switching.rows(plugs, now, zone),
      heater_rows: Heating.rows(socket.assigns.readings, now, zone),
      air: room_air(config, rooms, now)
    )
    |> load_lights()
  end

  defp load_lights(socket) do
    socket
    |> assign(now: Clock.now(), snapshots: Lights.snapshots())
    |> tick_while_starting()
    |> assign_sections()
  end

  # A room's sensors are matched by name until sensors take their room from the database too.
  defp room_air(config, rooms, now) do
    sensor_rooms = config |> Sensors.rooms() |> MapSet.new()

    for room <- rooms,
        MapSet.member?(sensor_rooms, room.name),
        reading = Sensors.room_reading(config, room.name, now),
        reading.values[:temperature] || reading.values[:co2],
        into: %{},
        do: {room.id, %{reading: reading, verdict: Sensors.air_verdict(reading)}}
  end

  defp assign_sections(socket) do
    %{rooms: rooms, snapshots: snapshots, air: air} = socket.assigns
    %{rows: rows, heater_rows: heater_rows, plug_rooms: plug_rooms} = socket.assigns
    summaries = summaries(heater_rows, snapshots, rows)
    # A filter for a kind the home has none of shows everything.
    filter = Enum.find_value(summaries, &(&1.kind == socket.assigns.filter && &1.kind))

    devices =
      Enum.map(heater_rows, &{:heater, &1.heater.room_id, &1}) ++
        Enum.map(snapshots, &{:lamp, &1.light.room_id, &1}) ++
        Enum.map(rows, &{:plug, plug_rooms[&1.plug.id], &1})

    by_room =
      devices
      |> Enum.filter(fn {kind, _room_id, _item} -> is_nil(filter) or kind == filter end)
      |> Enum.group_by(&elem(&1, 1))

    {placed, homeless} = Map.split(by_room, Enum.map(rooms, & &1.id))

    sections =
      Enum.map(rooms, &section(&1, Map.get(placed, &1.id, []), air)) ++
        [section(nil, homeless |> Map.values() |> List.flatten(), air)]

    assign(socket,
      nothing?: devices == [],
      sections: Enum.reject(sections, &(&1.count == 0)),
      summaries: summaries,
      shown_filter: filter,
      filter_name: filter && @filter_names[filter],
      any_lamp_lit: Enum.any?(snapshots, &Lights.lit?/1)
    )
  end

  defp section(room, items, air) do
    heaters = for {:heater, _room_id, row} <- items, do: row
    lamps = for {:lamp, _room_id, snapshot} <- items, do: snapshot
    plugs = for {:plug, _room_id, row} <- items, do: row

    %{
      id: if(room, do: "room-#{room.id}", else: "room-none"),
      room: room,
      name: if(room, do: room.name, else: "Ohne Raum"),
      air: room && air[room.id],
      heaters: heaters,
      lamps: lamps,
      plugs: plugs,
      count: length(items),
      lamp_lit: Enum.any?(lamps, &Lights.lit?/1),
      on_count:
        Enum.count(heaters, &Heating.Row.heating?/1) + Enum.count(lamps, &Lights.lit?/1) +
          Enum.count(plugs, &Switching.Row.lit?/1)
    }
  end

  defp summaries(heater_rows, snapshots, rows) do
    Enum.reject(
      [lamp_summary(snapshots), heater_summary(heater_rows), plug_summary(rows)],
      &is_nil/1
    )
  end

  defp lamp_summary([]), do: nil

  defp lamp_summary(snapshots) do
    case Enum.count(snapshots, &Lights.lit?/1) do
      0 -> %{kind: :lamp, label: "Lampen", plush: "lamp-off", text: "alle aus"}
      lit -> %{kind: :lamp, label: "Lampen", plush: "lamp", text: "#{lit} an"}
    end
  end

  defp heater_summary([]), do: nil

  defp heater_summary(heater_rows) do
    case Enum.count(heater_rows, &Heating.Row.heating?/1) do
      0 -> %{kind: :heater, label: "Heizungen", plush: "heater-off", text: "Frostschutz"}
      1 -> %{kind: :heater, label: "Heizungen", plush: "heater", text: "1 heizt"}
      heating -> %{kind: :heater, label: "Heizungen", plush: "heater", text: "#{heating} heizen"}
    end
  end

  defp plug_summary([]), do: nil

  defp plug_summary(rows) do
    case Enum.filter(rows, &Switching.Row.lit?/1) do
      [] ->
        %{kind: :plug, label: "Steckdosen", plush: "shelly-plug-off", text: "alle aus"}

      lit ->
        watts = lit |> Enum.map(&(&1.watt || 0)) |> Enum.sum()
        text = join_meta(["#{length(lit)} an", number(watts, unit: "W")])
        %{kind: :plug, label: "Steckdosen", plush: "shelly-plug", text: text}
    end
  end

  defp tick_while_starting(%{assigns: %{tick: nil, snapshots: snapshots}} = socket) do
    if Enum.any?(snapshots, &Lights.starting?/1),
      do: assign(socket, :tick, Process.send_after(self(), :tick, 1_000)),
      else: socket
  end

  defp tick_while_starting(socket), do: socket
end
