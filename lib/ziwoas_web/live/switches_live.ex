defmodule ZiwoasWeb.SwitchesLive do
  @moduledoc """
  The Schalten page: the lamps, then every switchable plug with its schedule.
  Schaltzeiten of a plug no longer in `ziwoas.yml` stay in the database unseen
  and switch nothing.

  `{:dashboard_live, _}` on the `dashboard` topic rebuilds the plug rows,
  `{:light_updated, _}` on `lights` the lamp tiles. The plug button, the lamp
  tiles (`ZiwoasWeb.LightEvents`) and the inline schedule editor — one per
  plug, for a new entry or in place of an existing one — are events here.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.LightsComponents
  import ZiwoasWeb.SwitchesComponents

  alias Ziwoas.{Clock, Config, Lights}
  alias Ziwoas.Switching.{Commander, Row, Rule, Rules, Window}
  alias ZiwoasWeb.LightEvents

  @failed "Schalten fehlgeschlagen — MQTT-Broker nicht erreichbar"

  @doc "The flash for a switch the broker did not take."
  def failed_message, do: @failed

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "lights")
    end

    {:ok, socket |> assign(page_title: "Schalten", editors: %{}) |> load()}
  end

  @impl true
  def handle_info({:dashboard_live, _deltas}, socket), do: {:noreply, load(socket)}

  def handle_info({:light_updated, _key}, socket),
    do: {:noreply, assign(socket, :snapshots, Lights.snapshots())}

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- The plug button and the lamp tiles ------------------------------------------

  @impl true
  def handle_event("switch_plug", %{"plug_id" => plug_id, "state" => state}, socket)
      when state in ~w[on off] do
    case plug(socket, plug_id) do
      nil ->
        {:noreply, socket}

      plug ->
        case Commander.switch(plug, String.to_existing_atom(state), :manual, mqtt()) do
          {:ok, _command} -> {:noreply, load(socket)}
          {:error, _message} -> {:noreply, put_flash(socket, :error, "#{plug.name}: #{@failed}")}
        end
    end
  end

  def handle_event("switch_plug", _params, socket), do: {:noreply, socket}

  def handle_event("light_command", params, socket) do
    case LightEvents.run(params) do
      {:ok, _light, _result} ->
        {:noreply, assign(socket, :snapshots, Lights.snapshots())}

      {:error, :commander} ->
        {:noreply, put_flash(socket, :error, LightEvents.failed_message())}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # --- The schedule editor -----------------------------------------------------------

  def handle_event("new_entry", %{"plug_id" => plug_id, "kind" => kind}, socket) do
    editor =
      case kind do
        "window" -> editor(:window, nil, Rules.change_window())
        _ -> editor(:rule, nil, Rules.change_single())
      end

    {:noreply, open_editor(socket, plug_id, editor)}
  end

  def handle_event("edit_entry", %{"plug_id" => plug_id, "kind" => kind, "id" => id}, socket) do
    editor =
      case kind do
        "window" ->
          with %Window{} = window <- Rules.window(plug_id, id),
               do: editor(:window, id, Rules.change_window(window))

        _ ->
          with %Rule{} = rule <- Rules.single(plug_id, id),
               do: editor(:rule, id, Rules.change_single(rule))
      end

    {:noreply, if(editor, do: open_editor(socket, plug_id, editor), else: socket)}
  end

  def handle_event("close_editor", %{"plug_id" => plug_id}, socket),
    do: {:noreply, close_editor(socket, plug_id)}

  def handle_event("validate_entry", %{"plug_id" => plug_id} = params, socket) do
    case socket.assigns.editors[plug_id] do
      nil ->
        {:noreply, socket}

      editor ->
        changeset = editor |> change(plug_id, params) |> Map.put(:action, :validate)
        {:noreply, put_editor(socket, plug_id, %{editor | form: to_form(changeset)})}
    end
  end

  def handle_event("save_entry", %{"plug_id" => plug_id} = params, socket) do
    with %{} = editor <- socket.assigns.editors[plug_id],
         %{} <- plug(socket, plug_id) do
      {:noreply, save(socket, plug_id, editor, params)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_enabled", params, socket) do
    case rules_of(socket, params) do
      [] ->
        {:noreply, socket}

      rules ->
        Rules.set_enabled(rules, params["enabled"] == "true")
        {:noreply, load(socket)}
    end
  end

  def handle_event("delete_entry", params, socket) do
    case rules_of(socket, params) do
      [] ->
        {:noreply, socket}

      rules ->
        Rules.delete(rules)
        {:noreply, socket |> put_flash(:info, "#{noun(params["kind"])} gelöscht.") |> load()}
    end
  end

  # --- Helpers ----------------------------------------------------------------------

  defp editor(kind, id, changeset), do: %{kind: kind, id: id, form: to_form(changeset)}

  defp change(%{kind: :window, id: id}, plug_id, params),
    do: Rules.change_window(Rules.window(plug_id, id || "") || %Window{}, params["window"] || %{})

  defp change(%{kind: :rule, id: id}, plug_id, params),
    do: Rules.change_single(stored_single(plug_id, id), params["rule"] || %{})

  defp stored_single(_plug_id, nil), do: %Rule{}
  defp stored_single(plug_id, id), do: Rules.single(plug_id, id) || %Rule{}

  defp save(socket, plug_id, %{kind: :window, id: id} = editor, params) do
    if id && is_nil(Rules.window(plug_id, id)) do
      socket |> close_editor(plug_id) |> load()
    else
      plug_id
      |> Rules.save_window(params["window"] || %{}, id)
      |> saved(socket, plug_id, editor)
    end
  end

  defp save(socket, plug_id, %{kind: :rule, id: id} = editor, params) do
    rule = id && Rules.single(plug_id, id)

    if id && is_nil(rule) do
      socket |> close_editor(plug_id) |> load()
    else
      plug_id
      |> Rules.save_single(params["rule"] || %{}, rule)
      |> saved(socket, plug_id, editor)
    end
  end

  defp saved({:ok, _saved}, socket, plug_id, editor) do
    socket
    |> close_editor(plug_id)
    |> put_flash(:info, "#{noun(editor.kind)} gespeichert.")
    |> load()
  end

  defp saved({:error, changeset}, socket, plug_id, editor),
    do: put_editor(socket, plug_id, %{editor | form: to_form(changeset)})

  defp noun(kind) when kind in [:window, "window"], do: "Zeitfenster"
  defp noun(_kind), do: "Schaltzeit"

  # A Zeitfenster is addressed by its group, an Einzelschaltung by its rule.
  defp rules_of(socket, %{"plug_id" => plug_id, "kind" => kind, "id" => id}) do
    cond do
      is_nil(plug(socket, plug_id)) -> []
      kind == "window" -> Rules.group(plug_id, id)
      true -> plug_id |> Rules.single(id) |> List.wrap()
    end
  end

  defp rules_of(_socket, _params), do: []

  defp open_editor(socket, plug_id, editor),
    do: if(plug(socket, plug_id), do: put_editor(socket, plug_id, editor), else: socket)

  defp put_editor(socket, plug_id, editor),
    do: update(socket, :editors, &Map.put(&1, plug_id, editor))

  defp close_editor(socket, plug_id), do: update(socket, :editors, &Map.delete(&1, plug_id))

  defp plug(socket, plug_id),
    do: Enum.find_value(socket.assigns.rows, &(&1.plug.id == plug_id && &1.plug))

  defp mqtt, do: Config.app_config().mqtt

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
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
        <.plug_card :for={row <- @rows} row={row} zone={@zone} editor={@editors[row.plug.id]} />
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
