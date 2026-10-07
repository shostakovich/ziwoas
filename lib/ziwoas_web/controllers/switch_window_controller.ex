defmodule ZiwoasWeb.SwitchWindowController do
  @moduledoc """
  The Zeitfenster as a resource (Rails' `SwitchWindowsController`): addressed
  by its group, never by one of its two rules, so pausing, editing and
  deleting always hit both halves. Answers Turbo Streams.
  """
  use ZiwoasWeb, :controller

  import ZiwoasWeb.ScheduleEditing

  alias Ziwoas.Switching.{Contracts, Rules, WindowForm}
  alias ZiwoasWeb.SwitchesComponents

  plug ZiwoasWeb.Owned,
       [task: :switch_schedule] when action in [:create, :update, :enabled, :delete]

  plug :fetch_plug

  def new(conn, _params), do: render_editor(conn, form(conn, %WindowForm{}))

  def create(conn, params) do
    changeset = Contracts.Window.changeset(window_attrs(params))

    if changeset.valid? do
      Rules.save_window(conn.assigns.plug.id, changeset.changes)
      render_entries(conn)
    else
      render_editor(
        conn,
        form(conn, WindowForm.from_changeset(changeset, error_messages(changeset))),
        422
      )
    end
  end

  def edit(conn, %{"group_id" => group_id}) do
    case group(conn, group_id) |> Rules.halves() do
      {on, off} -> render_row(conn, group_id, form(conn, WindowForm.for_group(group_id, on, off)))
      nil -> not_found(conn)
    end
  end

  def update(conn, %{"group_id" => group_id} = params) do
    if Rules.halves(group(conn, group_id)) do
      changeset = Contracts.Window.changeset(window_attrs(params))

      if changeset.valid? do
        Rules.save_window(conn.assigns.plug.id, changeset.changes, group_id)
        render_entries(conn)
      else
        form = WindowForm.from_changeset(changeset, error_messages(changeset), group_id)
        render_row(conn, group_id, form(conn, form), 422)
      end
    else
      not_found(conn)
    end
  end

  # Pausing has its own member route: a toggle carries one boolean and would
  # fall through a contract that demands times and weekdays.
  def enabled(conn, %{"group_id" => group_id} = params) do
    case group(conn, group_id) do
      [] ->
        not_found(conn)

      rules ->
        Rules.set_enabled(rules, Rules.cast_boolean(params["enabled"]))
        render_entries(conn)
    end
  end

  def delete(conn, %{"group_id" => group_id}) do
    case group(conn, group_id) do
      [] ->
        not_found(conn)

      rules ->
        Rules.delete(rules)
        render_entries(conn)
    end
  end

  defp group(conn, group_id), do: Rules.group(conn.assigns.plug.id, group_id)

  defp form(conn, form),
    do:
      ZiwoasWeb.TurboStream.component(&SwitchesComponents.window_form/1, %{
        plug: conn.assigns.plug,
        form: form
      })
end
