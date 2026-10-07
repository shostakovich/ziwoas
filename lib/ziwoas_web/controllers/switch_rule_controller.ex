defmodule ZiwoasWeb.SwitchRuleController do
  @moduledoc """
  The Einzelschaltung as a resource (Rails' `SwitchRulesController`): one rule,
  addressed by its own id, with an explicit direction. The mirror of
  `ZiwoasWeb.SwitchWindowController`. The leftover half of a group that lost
  its partner is reachable here; one half of an intact Zeitfenster is not.
  """
  use ZiwoasWeb, :controller

  import ZiwoasWeb.ScheduleEditing

  alias Ziwoas.Switching.{Contracts, Rules, SingleForm}
  alias ZiwoasWeb.SwitchesComponents

  plug ZiwoasWeb.Owned,
       [task: :switch_schedule] when action in [:create, :update, :enabled, :delete]

  plug :fetch_plug

  def new(conn, _params), do: render_editor(conn, form(conn, %SingleForm{}))

  def create(conn, params) do
    changeset = Contracts.Single.changeset(single_attrs(params))

    if changeset.valid? do
      Rules.save_single(conn.assigns.plug.id, changeset.changes)
      render_entries(conn)
    else
      render_editor(
        conn,
        form(conn, SingleForm.from_changeset(changeset, error_messages(changeset))),
        422
      )
    end
  end

  def edit(conn, %{"id" => id}) do
    case Rules.single(conn.assigns.plug.id, id) do
      nil -> not_found(conn)
      rule -> render_row(conn, rule.id, form(conn, SingleForm.for_rule(rule)))
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Rules.single(conn.assigns.plug.id, id) do
      nil ->
        not_found(conn)

      rule ->
        changeset = Contracts.Single.changeset(single_attrs(params))

        if changeset.valid? do
          Rules.save_single(conn.assigns.plug.id, changeset.changes, rule)
          render_entries(conn)
        else
          form = SingleForm.from_changeset(changeset, error_messages(changeset), rule.id)
          render_row(conn, rule.id, form(conn, form), 422)
        end
    end
  end

  def enabled(conn, %{"id" => id} = params) do
    case Rules.single(conn.assigns.plug.id, id) do
      nil ->
        not_found(conn)

      rule ->
        Rules.set_enabled([rule], Rules.cast_boolean(params["enabled"]))
        render_entries(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Rules.single(conn.assigns.plug.id, id) do
      nil ->
        not_found(conn)

      rule ->
        Rules.delete([rule])
        render_entries(conn)
    end
  end

  defp form(conn, form),
    do:
      ZiwoasWeb.TurboStream.component(&SwitchesComponents.single_form/1, %{
        plug: conn.assigns.plug,
        form: form
      })
end
