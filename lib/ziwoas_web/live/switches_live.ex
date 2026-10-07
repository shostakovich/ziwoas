defmodule ZiwoasWeb.SwitchesLive do
  @moduledoc """
  The Schalten page (Rails' `SwitchesController#index`): the lamps, then every
  switchable plug with its schedule. Schaltzeiten of a plug no longer in
  `ziwoas.yml` stay in the database unseen and switch nothing.

  Rails refreshes the plug heads over the `dashboard_live` Turbo stream; here
  `{:dashboard_live, _}` on the `dashboard` topic rebuilds the rows, and
  `{:light_updated, _}` on `lights` (Rails' `lights` stream) the lamp tiles.

  The controls are Rails' forms and links (first render identical); connected,
  their `phx-submit`/`phx-click` do what the Turbo round trips do on Rails' page:
  the plug button (`switching`), the lamp tiles (`lights`, `ZiwoasWeb.LightEvents`)
  and the inline schedule editors — new, edit, save, pause, delete — with
  `ZiwoasWeb.SwitchWindowController`'s and `SwitchRuleController`'s logic
  (`switch_schedule`). Each acts only while Phoenix owns its task.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents
  import ZiwoasWeb.SwitchesComponents

  alias Ziwoas.{Clock, Config, Lights, Ownership}
  alias Ziwoas.Switching.{Commander, Contracts, Row, Rules, SingleForm, WindowForm}
  alias ZiwoasWeb.{LightEvents, PlugSwitchController, ScheduleEditing}

  @topic "dashboard"
  @not_owner "Schalten fehlgeschlagen — Phoenix ist für diese Aufgabe nicht zuständig"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "lights")
    end

    {:ok,
     socket
     |> assign(page_title: "Schalten", errors: %{}, editors: %{}, editing: %{})
     |> load()}
  end

  @impl true
  def handle_info({:dashboard_live, _deltas}, socket), do: {:noreply, load(socket)}

  def handle_info({:light_updated, _key}, socket),
    do: {:noreply, assign(socket, :snapshots, Lights.snapshots())}

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- The plug button and the lamp tiles ------------------------------------------

  @impl true
  def handle_event("switch_plug", %{"plug_id" => plug_id, "state" => state}, socket) do
    with %{} = plug <- plug(socket, plug_id),
         true <- state in ~w[on off] do
      error = switch(plug, String.to_existing_atom(state))
      {:noreply, socket |> update(:errors, &put_or_delete(&1, plug_id, error)) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("light_command", params, socket) do
    case LightEvents.run(params) do
      {:ok, _light, _result} -> {:noreply, assign(socket, :snapshots, Lights.snapshots())}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # --- The schedule editors ----------------------------------------------------------

  def handle_event("new_entry", %{"plug_id" => plug_id, "kind" => kind}, socket) do
    editor =
      case kind do
        "window" -> {:window, %WindowForm{}}
        _ -> {:rule, %SingleForm{}}
      end

    {:noreply,
     with_plug(socket, plug_id, &update(&1, :editors, fn e -> Map.put(e, plug_id, editor) end))}
  end

  def handle_event("edit_entry", %{"plug_id" => plug_id, "kind" => kind, "id" => id}, socket) do
    editor =
      case kind do
        "window" ->
          with {on, off} <- plug_id |> Rules.group(id) |> Rules.halves(),
               do: {:window, WindowForm.for_group(id, on, off)}

        _ ->
          with %{} = rule <- Rules.single(plug_id, id), do: {:rule, SingleForm.for_rule(rule)}
      end

    socket =
      if editor,
        do:
          with_plug(
            socket,
            plug_id,
            &update(&1, :editing, fn e -> Map.put(e, plug_id, {id, editor}) end)
          ),
        else: socket

    {:noreply, socket}
  end

  def handle_event("close_editor", %{"plug_id" => plug_id}, socket),
    do: {:noreply, close_editors(socket, plug_id)}

  def handle_event("save_entry", %{"plug_id" => plug_id, "kind" => kind} = params, socket) do
    with %{} <- plug(socket, plug_id),
         true <- Ownership.owner?(:switch_schedule) do
      {:noreply, save(socket, plug_id, kind, params["id"], params)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_enabled", %{"plug_id" => plug_id} = params, socket),
    do:
      {:noreply,
       change_rules(
         socket,
         plug_id,
         params,
         &Rules.set_enabled(&1, Rules.cast_boolean(params["enabled"]))
       )}

  def handle_event("delete_entry", %{"plug_id" => plug_id} = params, socket),
    do: {:noreply, change_rules(socket, plug_id, params, &Rules.delete/1)}

  # --- Helpers ----------------------------------------------------------------------

  defp switch(plug, action) do
    if Ownership.acting?(:switching) do
      case Commander.switch(plug, action, :manual, Config.app_config().mqtt) do
        {:ok, _command} -> nil
        {:error, _message} -> PlugSwitchController.failed_message()
      end
    else
      @not_owner
    end
  end

  defp save(socket, plug_id, "window", id, params) do
    changeset = Contracts.Window.changeset(ScheduleEditing.window_attrs(params))
    group = id && Rules.halves(Rules.group(plug_id, id))

    cond do
      id && is_nil(group) ->
        socket |> close_editors(plug_id) |> load()

      changeset.valid? ->
        Rules.save_window(plug_id, changeset.changes, id)
        socket |> close_editors(plug_id) |> load()

      true ->
        form = WindowForm.from_changeset(changeset, ScheduleEditing.error_messages(changeset), id)
        reopen(socket, plug_id, id, {:window, form})
    end
  end

  defp save(socket, plug_id, _rule, id, params) do
    changeset = Contracts.Single.changeset(ScheduleEditing.single_attrs(params))
    rule = id && Rules.single(plug_id, id)

    cond do
      id && is_nil(rule) ->
        socket |> close_editors(plug_id) |> load()

      changeset.valid? ->
        Rules.save_single(plug_id, changeset.changes, rule)
        socket |> close_editors(plug_id) |> load()

      true ->
        form =
          SingleForm.from_changeset(
            changeset,
            ScheduleEditing.error_messages(changeset),
            rule && rule.id
          )

        reopen(socket, plug_id, id, {:rule, form})
    end
  end

  # A new entry is composed below the list, an existing one in place of its row.
  defp reopen(socket, plug_id, nil, editor),
    do: update(socket, :editors, &Map.put(&1, plug_id, editor))

  defp reopen(socket, plug_id, id, editor),
    do: update(socket, :editing, &Map.put(&1, plug_id, {id, editor}))

  defp change_rules(socket, plug_id, %{"kind" => kind, "id" => id}, fun) do
    rules =
      case kind do
        "window" -> Rules.group(plug_id, id)
        _ -> plug_id |> Rules.single(id) |> List.wrap()
      end

    if plug(socket, plug_id) && rules != [] && Ownership.owner?(:switch_schedule) do
      fun.(rules)
      load(socket)
    else
      socket
    end
  end

  defp change_rules(socket, _plug_id, _params, _fun), do: socket

  defp close_editors(socket, plug_id) do
    socket
    |> update(:editors, &Map.delete(&1, plug_id))
    |> update(:editing, &Map.delete(&1, plug_id))
  end

  defp with_plug(socket, plug_id, fun),
    do: if(plug(socket, plug_id), do: fun.(socket), else: socket)

  defp plug(socket, plug_id),
    do: Enum.find_value(socket.assigns.rows, &(&1.plug.id == plug_id && &1.plug))

  defp put_or_delete(map, key, nil), do: Map.delete(map, key)
  defp put_or_delete(map, key, value), do: Map.put(map, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <h1 class="h2 mb-3">Schalten</h1>

      <div>
        <section :if={@rows == []} class="card card-body mb-3">
          <h2 class="card-title h5">Keine schaltbaren Steckdosen</h2>
          <p class="text-body-secondary mb-0">
            Markiere Verbraucher in <code>ziwoas.yml</code> mit <code>switchable: true</code>.
          </p>
        </section>

        <%= if @snapshots != [] do %>
          <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Lampen</h2>
          <.light_card :for={snapshot <- @snapshots} snapshot={snapshot} />
        <% end %>

        <h2 :if={@rows != []} class="h6 text-uppercase text-body-secondary mt-4 mb-2">Steckdosen</h2>
        <.plug_card
          :for={row <- @rows}
          row={row}
          zone={@zone}
          error={@errors[row.plug.id]}
          editor={@editors[row.plug.id]}
          editing={@editing[row.plug.id]}
        />
      </div>
    </Layouts.app>
    """
  end

  defp load(socket) do
    config = Config.app_config()
    zone = config.location.timezone
    plugs = Enum.filter(config.plugs, & &1.switchable)

    assign(socket,
      zone: zone,
      rows: Row.build_all(plugs, Clock.now(), zone),
      snapshots: Lights.snapshots()
    )
  end
end
