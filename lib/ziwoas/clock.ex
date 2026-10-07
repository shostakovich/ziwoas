defmodule Ziwoas.Clock do
  @moduledoc false

  @callback utc_now() :: DateTime.t()

  @source Application.compile_env(:ziwoas, :clock, DateTime)

  @spec now() :: DateTime.t()
  def now, do: with_usec_precision(@source.utc_now())

  @spec now(String.t()) :: DateTime.t()
  def now(zone), do: DateTime.shift_zone!(now(), zone)

  @spec unix_now() :: integer
  def unix_now, do: DateTime.to_unix(now())

  @spec today(String.t()) :: Date.t()
  def today(zone), do: zone |> now() |> DateTime.to_date()

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
