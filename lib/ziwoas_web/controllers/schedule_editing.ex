defmodule ZiwoasWeb.ScheduleEditing do
  @moduledoc """
  What `SwitchWindowController` and `SwitchRuleController` share (Rails'
  `ScheduleEditing`): the plug in the URL and the Turbo targets they write
  back into. They differ only in what a row is — a group or a single rule.
  """
  import Plug.Conn

  alias Ziwoas.{Clock, Config, Form}
  alias Ziwoas.Switching.Row
  alias ZiwoasWeb.{SwitchesComponents, TurboStream}

  @doc "Plug: assigns the plug; 404 for an unknown one, 422 for one that does not switch."
  def fetch_plug(conn, _opts) do
    case Enum.find(Config.app_config().plugs, &(&1.id == conn.params["plug_id"])) do
      nil -> conn |> head(:not_found) |> halt()
      %{switchable: false} -> conn |> head(:unprocessable_entity) |> halt()
      plug -> assign(conn, :plug, plug)
    end
  end

  @doc """
  The count and the status line sit outside the rules container and both can
  move with any write, so all three regions are streamed together.
  """
  def render_entries(conn) do
    plug = conn.assigns.plug
    zone = Config.app_config().location.timezone
    row = Row.build(plug, Clock.now(), zone)

    TurboStream.send(conn, [
      {"replace", "sw_rules_#{plug.id}",
       TurboStream.component(&SwitchesComponents.entries/1, %{plug: plug, entries: row.entries})},
      {"replace", "sw_count_#{plug.id}",
       TurboStream.component(&SwitchesComponents.summary/1, %{row: row})},
      {"replace", "sw_head_#{plug.id}",
       TurboStream.component(&SwitchesComponents.head/1, %{row: row, zone: zone})}
    ])
  end

  @doc "A new entry is composed in the editor slot below the list."
  def render_editor(conn, rendered, status \\ 200),
    do:
      TurboStream.send(conn, [{"update", "sw_editor_#{conn.assigns.plug.id}", rendered}], status)

  @doc "An existing entry is edited in place of its row."
  def render_row(conn, id, rendered, status \\ 200),
    do:
      TurboStream.send(
        conn,
        [{"replace", "sw_entry_#{conn.assigns.plug.id}_#{id}", rendered}],
        status
      )

  def not_found(conn), do: head(conn, :not_found)

  @doc "Rails' `head`: no body, the request's format as the content type."
  def head(conn, status), do: conn |> put_resp_content_type("text/html") |> send_resp(status, "")

  @doc """
  The weekday checkboxes ship a blank first value so that unticking them all
  still sends the key (`Array(raw).reject(&:blank?)`).
  """
  def weekdays(nil), do: []
  def weekdays(days) when is_list(days), do: Enum.reject(days, &Form.blank?/1)
  def weekdays(%{} = days), do: [days]
  def weekdays(day), do: if(Form.blank?(day), do: [], else: [day])

  def error_messages(changeset), do: changeset |> Form.messages() |> Enum.uniq()

  @doc "The form scope's raw values (`params.fetch(scope, {})`)."
  def scope(params, name) do
    case params[name] do
      %{} = given -> given
      _ -> %{}
    end
  end

  @doc "What the Zeitfenster contract gets from a request (`window_attrs`)."
  def window_attrs(params) do
    attrs = scope(params, "switch_window")

    %{
      "on_at_time" => attrs["on_at_time"],
      "off_at_time" => attrs["off_at_time"],
      "days" => weekdays(attrs["days"])
    }
  end

  @doc "What the Einzelschaltung contract gets from a request (`single_attrs`)."
  def single_attrs(params) do
    attrs = scope(params, "switch_rule")

    %{
      "at_minute_time" => attrs["at_minute_time"],
      "action" => attrs["action"],
      "days" => weekdays(attrs["days"])
    }
  end
end
