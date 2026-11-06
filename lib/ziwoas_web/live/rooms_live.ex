defmodule ZiwoasWeb.RoomsLive do
  @moduledoc """
  The rooms Schalten groups by: add, rename, reorder and delete them (ADR-0014). A deleted
  room's devices stand under „Ohne Raum“ until they get another.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.ErrorSummary, only: [error_summary: 1]

  alias Ziwoas.{Clock, Config, Heating, Lights, Rooms}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Räume", editing: nil)
     |> assign_form(Rooms.change())
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"room" => params}, socket) do
    changeset =
      socket.assigns.editing |> base() |> Rooms.change(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"room" => params}, socket) do
    result =
      case socket.assigns.editing do
        nil -> Rooms.create(params)
        room -> Rooms.rename(room, params)
      end

    case result do
      {:ok, room} ->
        message =
          if socket.assigns.editing,
            do: "Raum „#{room.name}“ umbenannt.",
            else: "Raum „#{room.name}“ angelegt."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(editing: nil)
         |> assign_form(Rooms.change())
         |> load()}

      {:error, changeset} ->
        {:noreply, socket |> clear_flash() |> assign_form(changeset)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Rooms.get(id) do
      nil ->
        {:noreply, load(socket)}

      room ->
        {:noreply,
         socket
         |> assign(editing: room)
         |> assign_form(Rooms.change(room))
         |> push_event("focus_return", %{ids: ["room_form_name"]})}
    end
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, socket |> assign(editing: nil) |> assign_form(Rooms.change())}

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ~w[up down] do
    if room = Rooms.get(id), do: Rooms.move(room, String.to_existing_atom(direction))
    {:noreply, load(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Rooms.get(id) do
      nil ->
        {:noreply, load(socket)}

      room ->
        {:noreply, socket |> deleted(room, Rooms.delete(room)) |> load()}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp deleted(socket, room, {:ok, _deleted}) do
    editing = socket.assigns.editing
    socket = if editing && editing.id == room.id, do: assign(socket, editing: nil), else: socket

    socket
    |> put_flash(:info, "Raum „#{room.name}“ gelöscht.")
    |> assign_form(Rooms.change())
  end

  defp deleted(socket, _room, {:error, _gone}), do: socket

  defp base(nil), do: %Rooms.Room{}
  defp base(room), do: room

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:narrow}>
      <.header back={~p"/switches"} back_label="Schalten">
        Räume
        <:subtitle>In dieser Reihenfolge stehen die Räume auf Schalten.</:subtitle>
      </.header>

      <div class="flex flex-col gap-8" id="rooms" phx-hook="FocusReturn">
        <section aria-label="Räume">
          <.list :if={@rooms != []} id="room_list">
            <.list_row
              :for={{room, index} <- Enum.with_index(@rooms)}
              id={"room-#{room.id}"}
              title={room.name}
            >
              <:meta>{devices_label(@counts[room.id] || 0)}</:meta>
              <:action
                id={"room-#{room.id}-up"}
                label="Nach oben"
                icon="arrow-up"
                disabled={index == 0}
                on_click={JS.push("move", value: %{id: room.id, direction: "up"})}
              />
              <:action
                id={"room-#{room.id}-down"}
                label="Nach unten"
                icon="arrow-down"
                disabled={index == length(@rooms) - 1}
                on_click={JS.push("move", value: %{id: room.id, direction: "down"})}
              />
              <:action
                id={"room-#{room.id}-edit"}
                label="Umbenennen"
                icon="pencil"
                on_click={JS.push("edit", value: %{id: room.id})}
              />
              <:action
                id={"room-#{room.id}-delete"}
                label="Löschen"
                icon="trash-2"
                danger
                confirm={"„#{room.name}“ löschen?"}
                confirm_text={delete_text(@counts[room.id] || 0)}
                on_click={JS.push("delete", value: %{id: room.id})}
              />
            </.list_row>
          </.list>
          <.empty_state :if={@rooms == []} id="rooms_empty" title="Noch keine Räume">
            Lege den ersten Raum an. Danach wählst du auf der Seite jedes Geräts, wo es steht.
          </.empty_state>
          <p :if={@homeless > 0} id="rooms_homeless" class="mt-3 text-sm text-base-content/70">
            {homeless_text(@homeless)}
          </p>
        </section>

        <.form
          for={@form}
          id="room_form"
          phx-hook="Setzkasten.Components.Forms.FocusInvalid"
          phx-change="validate"
          phx-submit="save"
        >
          <.section_heading level={2} size={:sm}>
            {if @editing, do: "„#{@editing.name}“ umbenennen", else: "Raum anlegen"}
          </.section_heading>
          <.error_summary id="room_form_errors" form={@form} class="mb-4" />
          <.input field={@form[:name]} id="room_form_name" label="Name" required />
          <.action_bar>
            <.button :if={@editing} id="room_form_cancel" phx-click="cancel">Abbrechen</.button>
            <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
              {if @editing, do: "Umbenennen", else: "Anlegen"}
            </.button>
          </.action_bar>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp homeless_text(1), do: "1 Gerät noch ohne Raum. Es steht auf Schalten unter „Ohne Raum“."

  defp homeless_text(count),
    do: "#{count} Geräte noch ohne Raum. Sie stehen auf Schalten unter „Ohne Raum“."

  defp devices_label(1), do: "1 Gerät"
  defp devices_label(count), do: "#{count} Geräte"

  defp delete_text(0), do: nil
  defp delete_text(1), do: "1 Gerät steht danach unter „Ohne Raum“."
  defp delete_text(count), do: "#{devices_label(count)} stehen danach unter „Ohne Raum“."

  defp load(socket) do
    rooms = Rooms.list()
    plug_rooms = Rooms.plug_rooms()
    config = Config.get()
    switchable = for plug <- config.plugs, plug.switchable, do: plug.id
    heater_rows = Heating.rows(Heating.readings(), Clock.now(), config.location.timezone)

    room_ids =
      Enum.map(Lights.lights(), & &1.room_id) ++
        Enum.map(heater_rows, & &1.heater.room_id) ++
        Enum.map(switchable, &plug_rooms[&1])

    assign(socket,
      rooms: rooms,
      counts: Enum.frequencies(room_ids),
      homeless: Enum.count(room_ids, &is_nil/1)
    )
  end
end
