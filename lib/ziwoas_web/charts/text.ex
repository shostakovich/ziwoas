defmodule ZiwoasWeb.Charts.Text do
  @moduledoc false
  import ZiwoasWeb.Format, only: [number: 2]

  @months ~w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez]
  @weekdays ~w[So Mo Di Mi Do Fr Sa]

  @spec month_name(1..12) :: String.t()
  def month_name(month), do: Enum.at(@months, month - 1)

  @spec weekday(Date.t()) :: String.t()
  def weekday(date), do: Enum.at(@weekdays, rem(Date.day_of_week(date), 7))

  @spec hour(integer, :hour | :clock) :: String.t()
  def hour(hour, :hour), do: String.pad_leading(Integer.to_string(hour), 2, "0")
  def hour(hour, :clock), do: hour(hour, :hour) <> ":00"

  @spec mean_watts(number | nil) :: String.t()
  def mean_watts(nil), do: "keine Daten"
  def mean_watts(value), do: "Ø #{number(value, unit: "W")}"

  @spec panel_name(atom) :: String.t()
  def panel_name(key), do: "Panel #{String.replace_prefix(Atom.to_string(key), "pv", "")}"

  @spec days(integer) :: String.t()
  def days(1), do: "Tag"
  def days(_count), do: "Tage"
end
