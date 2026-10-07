defmodule Ziwoas.Clock do
  @moduledoc """
  The one source of "now": every reading of the current instant or date goes
  through it, so tests can pin the instant.

  The instant comes from `config :ziwoas, :clock`, a module with `utc_now/0`
  (this behaviour), fixed at compile time: `DateTime` itself, in tests
  `Ziwoas.TestClock` (test/support), which can freeze it.
  """

  @callback utc_now() :: DateTime.t()

  @source Application.compile_env(:ziwoas, :clock, DateTime)

  @doc "The current instant in UTC, microsecond precision."
  @spec now() :: DateTime.t()
  def now, do: with_usec_precision(@source.utc_now())

  @doc "The current instant in `zone`."
  @spec now(String.t()) :: DateTime.t()
  def now(zone), do: DateTime.shift_zone!(now(), zone)

  @doc "Unix seconds, truncated."
  @spec unix_now() :: integer
  def unix_now, do: DateTime.to_unix(now())

  @doc "The calendar date in `zone`, like `zone.today` or `Date.current`."
  @spec today(String.t()) :: Date.t()
  def today(zone), do: zone |> now() |> DateTime.to_date()

  @doc "The calendar date in UTC."
  @spec utc_today() :: Date.t()
  def utc_today, do: DateTime.to_date(now())

  @doc """
  Parses an ISO 8601 instant with offset into UTC with microsecond precision, as
  `:utc_datetime_usec` fields take it; raises on anything else.
  """
  @spec parse!(DateTime.t() | String.t()) :: DateTime.t()
  def parse!(%DateTime{} = instant),
    do: instant |> DateTime.shift_zone!("Etc/UTC") |> with_usec_precision()

  def parse!(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, instant, _offset} -> with_usec_precision(instant)
      {:error, reason} -> raise ArgumentError, "invalid instant #{inspect(text)}: #{reason}"
    end
  end

  defp with_usec_precision(%DateTime{microsecond: {usec, _}} = instant),
    do: %{instant | microsecond: {usec, 6}}
end
