defmodule Ziwoas.GermanNumber do
  @moduledoc """
  Deprecated delegate to `ZiwoasWeb.Format` for the domain callers that still
  format text (`Ziwoas.Solakon.History`); goes once they return plain numbers.
  """

  defdelegate format(value, opts \\ []), to: ZiwoasWeb.Format, as: :number
  defdelegate flow(value, opts), to: ZiwoasWeb.Format
end
