defmodule ZiwoasWeb.ErrorSummary do
  @moduledoc false
  use ZiwoasWeb, :html

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :class, :any, default: nil

  def error_summary(assigns) do
    assigns = assign(assigns, :count, invalid_fields(assigns.form))

    ~H"""
    <.alert :if={@count > 0} id={@id} tone={:error} title={title(@count)} class={@class}>
      {if @count == 1,
        do: "Bitte prüfe das markierte Feld.",
        else: "Bitte prüfe die markierten Felder."}
    </.alert>
    """
  end

  # Only a refused save counts; phx-change marks its changesets :validate.
  defp invalid_fields(%{action: action, errors: errors}) when action not in [nil, :validate],
    do: errors |> Keyword.keys() |> Enum.uniq() |> length()

  defp invalid_fields(_form), do: 0

  defp title(1), do: "1 Feld ist noch nicht richtig"
  defp title(count), do: "#{count} Felder sind noch nicht richtig"
end
