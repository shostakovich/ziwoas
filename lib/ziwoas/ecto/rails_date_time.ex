defmodule Ziwoas.Ecto.RailsDateTime do
  @moduledoc """
  A UTC timestamp stored the way ActiveRecord stores `datetime(6)` in SQLite:
  `YYYY-MM-DD HH:MM:SS` followed by `.ffffff` only when the microseconds are non-zero.

  ecto_sqlite3's own `:datetime_type` options either write a `T` (`:iso8601`) or drop
  the microseconds (`:text_datetime`); both break SQL string comparisons against
  rows Rails wrote. Values load as `DateTime` in `Etc/UTC` with microsecond precision.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(%DateTime{} = value), do: {:ok, normalize(DateTime.shift_zone!(value, "Etc/UTC"))}
  def cast(%NaiveDateTime{} = value), do: {:ok, normalize(DateTime.from_naive!(value, "Etc/UTC"))}

  def cast(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> cast(datetime)
      {:error, :missing_offset} -> load(value)
      {:error, _} -> :error
    end
  end

  def cast(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> cast(naive)
      {:error, _} -> :error
    end
  end

  def load(_), do: :error

  @impl true
  def dump(%DateTime{time_zone: "Etc/UTC"} = value), do: {:ok, format(value)}
  def dump(_), do: :error

  @impl true
  def equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  def equal?(a, b), do: a == b

  @doc "Autogenerate hook for `timestamps/1`: ActiveRecord's `Time.now`, through `Ziwoas.Clock`."
  def utc_now, do: Ziwoas.Clock.now()

  defp normalize(%DateTime{microsecond: {usec, _}} = value),
    do: %{value | microsecond: {usec, 6}}

  defp format(%DateTime{microsecond: {usec, _}} = value) do
    base = Calendar.strftime(value, "%Y-%m-%d %H:%M:%S")

    if usec == 0,
      do: base,
      else: base <> "." <> String.pad_leading(Integer.to_string(usec), 6, "0")
  end
end
