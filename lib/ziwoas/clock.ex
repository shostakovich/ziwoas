defmodule Ziwoas.Clock do
  @moduledoc """
  The one source of "now": every reading of the current instant or date goes
  through it, so tests can pin the instant.

  Resolution order:

    1. a process override (`freeze/1`), also seen by processes the freezing
       process started (`$callers`, e.g. a LiveView under test); test support,
       read only with `config :ziwoas, clock_process_override: true`;
    2. the system clock.

  A frozen instant stands still.
  """

  @key {__MODULE__, :now}

  @doc "The current instant in UTC, microsecond precision."
  @spec now() :: DateTime.t()
  def now do
    case frozen() do
      nil -> DateTime.utc_now()
      instant -> instant
    end
    |> with_usec_precision()
  end

  @doc "The current instant in `zone`."
  @spec now(String.t()) :: DateTime.t()
  def now(zone), do: DateTime.shift_zone!(now(), zone)

  @doc "Unix seconds, truncated like Ruby's `Time#to_i`."
  @spec unix_now() :: integer
  def unix_now, do: DateTime.to_unix(now())

  @doc "The calendar date in `zone`, like `zone.today` or `Date.current`."
  @spec today(String.t()) :: Date.t()
  def today(zone), do: zone |> now() |> DateTime.to_date()

  @doc "The calendar date in UTC."
  @spec utc_today() :: Date.t()
  def utc_today, do: DateTime.to_date(now())

  @doc "Pins now for this process (and the processes it starts) until `unfreeze/0`."
  @spec freeze(DateTime.t() | String.t()) :: :ok
  def freeze(instant) do
    Process.put(@key, parse!(instant))
    :ok
  end

  @spec unfreeze() :: :ok
  def unfreeze do
    Process.delete(@key)
    :ok
  end

  @doc "Parses an ISO 8601 instant with offset into UTC; raises on anything else."
  @spec parse!(DateTime.t() | String.t()) :: DateTime.t()
  def parse!(%DateTime{} = instant), do: DateTime.shift_zone!(instant, "Etc/UTC")

  def parse!(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, instant, _offset} -> instant
      {:error, reason} -> raise ArgumentError, "invalid instant #{inspect(text)}: #{reason}"
    end
  end

  defp frozen do
    if Application.get_env(:ziwoas, :clock_process_override, false),
      do: process_override([self() | Process.get(:"$callers", [])])
  end

  defp process_override([]), do: nil

  defp process_override([pid | rest]) do
    value =
      if pid == self() do
        Process.get(@key)
      else
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} -> List.keyfind(dictionary, @key, 0) |> elem_or_nil()
          nil -> nil
        end
      end

    value || process_override(rest)
  end

  defp elem_or_nil({_key, value}), do: value
  defp elem_or_nil(nil), do: nil

  defp with_usec_precision(%DateTime{microsecond: {usec, _}} = instant),
    do: %{instant | microsecond: {usec, 6}}
end
