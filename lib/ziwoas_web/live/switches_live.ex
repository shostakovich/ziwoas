defmodule ZiwoasWeb.SwitchesLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents
  import ZiwoasWeb.SwitchesComponents

  alias Ziwoas.{Clock, Config, Heating, Lights, Plugs, Switching}
  alias ZiwoasWeb.LightEvents

  @failed "Schalten fehlgeschlagen — Steckdose nicht erreichbar"
  @rejected "Schalten fehlgeschlagen — Steckdose lehnt ab"
  @heater_failed "Schalten fehlgeschlagen — Heizung nicht erreichbar"
  @heat_c_failed "Heiztemperatur nicht geändert — Heizung nicht erreichbar"
  def failed_message, do: @failed

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Plugs.subscribe()
      Lights.subscribe()
      Heating.subscribe()
    end

    {:ok,
     socket
     |> assign(page_title: "Schalten", editors: %{}, tick: nil, pending: MapSet.new())
     |> assign(readings: Heating.readings())
     |> load()}
  end

  @impl true
  def handle_info({:live, _deltas}, socket), do: {:noreply, load(socket)}

  def handle_info({:updated, _key}, socket), do: {:noreply, load_lights(socket)}

  def handle_info({:heaters, readings}, socket),
    do: {:noreply, socket |> assign(readings: readings) |> load_heaters()}

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
    heater_state = if state == "heat", do: :heat, else: :frost

    {:noreply,
     start_for_heater(socket, {:switch_heater, key}, fn -> Heating.switch(key, heater_state) end)}
  end

  def handle_event("heat_c", %{"heater_key" => key, "step" => step}, socket)
      when step in ~w[up down] do
    direction = if step == "up", do: :up, else: :down

    {:noreply,
     start_for_heater(socket, {:heat_c, key}, fn -> Heating.step_heat_c(key, direction) end)}
  end

  def handle_event("switch_plug", %{"plug_id" => plug_id, "state" => state}, socket)
      when state in ~w[on off] do
    action = if state == "on", do: :on, else: :off

    case plug(socket, plug_id) do
      nil ->
        {:noreply, socket}

      plug ->
        {:noreply,
         start_unless_pending(socket, {:switch, plug.id}, fn ->
           Switching.switch(plug, action, :manual)
         end)}
    end
  end

  def handle_event("light_command", %{"light_key" => key} = params, socket),
    do:
      {:noreply,
       start_unless_pending(socket, {:light_command, key}, fn -> LightEvents.run(params) end)}

  def handle_event("new_entry", %{"kind" => kind} = params, socket) do
    with {:ok, owner} <- owner(socket, params),
         {:ok, kind} <- kind(owner, kind) do
      {:noreply, put_editor(socket, owner, editor(kind, nil, change(owner, kind, nil, %{})))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_entry", %{"kind" => kind, "id" => id} = params, socket)
      when is_binary(id) do
    with {:ok, owner} <- owner(socket, params),
         {:ok, kind} <- kind(owner, kind),
         entry when not is_nil(entry) <- find(owner, kind, id) do
      {:noreply, put_editor(socket, owner, editor(kind, id, change(owner, kind, entry, %{})))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_editor", params, socket) do
    case owner(socket, params) do
      {:ok, owner} -> {:noreply, close_editor(socket, owner)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("validate_entry", params, socket) do
    with {:ok, owner} <- owner(socket, params),
         %{} = editor <- socket.assigns.editors[owner] do
      changeset =
        owner
        |> change(editor.kind, stored(owner, editor), attrs(params, editor.kind))
        |> Map.put(:action, :validate)

      {:noreply, put_editor(socket, owner, %{editor | form: to_form(changeset)})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_entry", params, socket) do
    with {:ok, owner} <- owner(socket, params),
         %{} = editor <- socket.assigns.editors[owner] do
      {:noreply, save(socket, owner, editor, params)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_enabled", %{"kind" => kind, "id" => id} = params, socket)
      when is_binary(id) do
    with {:ok, owner} <- owner(socket, params),
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
    with {:ok, owner} <- owner(socket, params),
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
  def handle_async(name, result, socket),
    do: {:noreply, socket |> update(:pending, &MapSet.delete(&1, name)) |> settle(name, result)}

  defp start_for_heater(socket, {_kind, key} = name, fun),
    do: if(heater(socket, key), do: start_unless_pending(socket, name, fun), else: socket)

  defp start_unless_pending(socket, name, fun) do
    if MapSet.member?(socket.assigns.pending, name),
      do: socket,
      else: socket |> update(:pending, &MapSet.put(&1, name)) |> start_async(name, fun)
  end

  defp settle(socket, {:switch, _plug_id}, {:ok, {:ok, _command}}), do: load(socket)

  defp settle(socket, {:switch, plug_id}, result) do
    name = Enum.find_value(socket.assigns.rows, plug_id, &(&1.plug.id == plug_id && &1.plug.name))
    put_flash(socket, :error, "#{name}: #{failure(result)}")
  end

  defp settle(socket, {kind, _key}, {:ok, {:ok, _result}}) when kind in [:switch_heater, :heat_c],
    do: load_heaters(socket)

  defp settle(socket, {kind, _key}, {:ok, {:error, reason}})
       when kind in [:switch_heater, :heat_c] and reason in [:limit, :not_found],
       do: load_heaters(socket)

  defp settle(socket, {kind, key}, _failed) when kind in [:switch_heater, :heat_c] do
    message = if kind == :switch_heater, do: @heater_failed, else: @heat_c_failed

    name =
      Enum.find_value(socket.assigns.heater_rows, key, &(&1.heater.key == key && &1.heater.name))

    socket |> put_flash(:error, "#{name}: #{message}") |> load_heaters()
  end

  defp settle(socket, {:light_command, _key}, {:ok, {:ok, _light, _result}}),
    do: load_lights(socket)

  defp settle(socket, {:light_command, _key}, {:ok, {:error, reason}})
       when reason in [:not_found, :invalid],
       do: socket

  defp settle(socket, {:light_command, _key}, _unreachable),
    do: put_flash(socket, :error, LightEvents.failed_message())

  defp failure({:ok, {:error, {:rejected, _reason}}}), do: @rejected
  defp failure(_result), do: @failed

  defp owner(socket, %{"heater_key" => key}),
    do: if(heater(socket, key), do: {:ok, {:heater, key}}, else: :error)

  defp owner(socket, %{"plug_id" => plug_id}),
    do: if(plug(socket, plug_id), do: {:ok, {:plug, plug_id}}, else: :error)

  defp owner(_socket, _params), do: :error

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

  defp save(socket, owner, editor, params) do
    entry = stored(owner, editor)

    if editor.id && is_nil(entry) do
      socket |> close_editor(owner) |> load()
    else
      case store(owner, editor, entry, attrs(params, editor.kind)) do
        {:ok, _saved} ->
          socket
          |> close_editor(owner)
          |> put_flash(:info, "#{noun(editor.kind)} gespeichert.")
          |> load()

        {:error, changeset} ->
          socket |> clear_flash() |> put_editor(owner, %{editor | form: to_form(changeset)})
      end
    end
  end

  defp noun(:window), do: "Zeitfenster"
  defp noun(:rule), do: "Schaltzeit"

  defp put_editor(socket, owner, editor),
    do: update(socket, :editors, &Map.put(&1, owner, editor))

  defp close_editor(socket, owner) do
    case socket.assigns.editors[owner] do
      nil ->
        socket

      editor ->
        socket
        |> update(:editors, &Map.delete(&1, owner))
        |> push_event("focus_return", %{ids: focus_return(owner, editor)})
    end
  end

  defp plug(socket, plug_id),
    do: Enum.find_value(socket.assigns.rows, &(&1.plug.id == plug_id && &1.plug))

  defp heater(socket, key),
    do: Enum.find_value(socket.assigns.heater_rows, &(&1.heater.key == key && &1.heater))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:default}>
      <.header>Schalten</.header>

      <div class="flex flex-col gap-8">
        <section :if={@snapshots != []} id="sw_lamps" aria-labelledby="sw_lamps_heading">
          <.section_heading id="sw_lamps_heading">Lampen</.section_heading>
          <div class="grid items-start gap-3 md:grid-cols-2 md:gap-6">
            <.light_card
              :for={snapshot <- @snapshots}
              snapshot={snapshot}
              now={@now}
              pending={MapSet.member?(@pending, {:light_command, snapshot.light.key})}
            />
          </div>
        </section>

        <section
          :if={@heater_rows != []}
          id="sw_heaters"
          aria-labelledby="sw_heaters_heading"
          phx-hook="FocusReturn"
        >
          <.section_heading id="sw_heaters_heading">Heizungen</.section_heading>
          <div class="grid items-start gap-3 md:grid-cols-2 md:gap-6">
            <.heater_card
              :for={row <- @heater_rows}
              row={row}
              zone={@zone}
              editor={@editors[{:heater, row.heater.key}]}
              pending={MapSet.member?(@pending, {:switch_heater, row.heater.key})}
              heat_pending={MapSet.member?(@pending, {:heat_c, row.heater.key})}
            />
          </div>
        </section>

        <section id="sw_plugs" aria-labelledby="sw_plugs_heading" phx-hook="FocusReturn">
          <.section_heading id="sw_plugs_heading">Steckdosen</.section_heading>
          <.empty_state :if={@rows == []} plush="plug" title="Keine schaltbaren Steckdosen">
            Markiere Verbraucher in <code>ziwoas.yml</code> mit <code>switchable: true</code>.
          </.empty_state>
          <div :if={@rows != []} class="grid items-start gap-3 md:grid-cols-2 md:gap-6">
            <.plug_card
              :for={row <- @rows}
              row={row}
              zone={@zone}
              editor={@editors[{:plug, row.plug.id}]}
              pending={MapSet.member?(@pending, {:switch, row.plug.id})}
            />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load(socket) do
    config = Config.get()
    zone = config.location.timezone
    plugs = Enum.filter(config.plugs, & &1.switchable)

    socket
    |> assign(zone: zone, rows: Switching.rows(plugs, Clock.now(), zone))
    |> load_heaters()
    |> load_lights()
  end

  defp load_heaters(socket),
    do:
      assign(socket,
        heater_rows: Heating.rows(socket.assigns.readings, Clock.now(), socket.assigns.zone)
      )

  defp load_lights(socket) do
    socket
    |> assign(now: Clock.now(), snapshots: Lights.snapshots())
    |> tick_while_starting()
  end

  defp tick_while_starting(%{assigns: %{tick: nil, snapshots: snapshots}} = socket) do
    if Enum.any?(snapshots, &Lights.starting?/1),
      do: assign(socket, :tick, Process.send_after(self(), :tick, 1_000)),
      else: socket
  end

  defp tick_while_starting(socket), do: socket
end
