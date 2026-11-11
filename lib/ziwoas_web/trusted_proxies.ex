defmodule ZiwoasWeb.TrustedProxies do
  @moduledoc """
  The peers whose `X-Remote-User` counts (ADR-0016): the gate's proxy in front of ZiWoAS.
  `config :ziwoas, :trusted_proxies` lists exact addresses (`127.0.0.1`) or CIDR ranges
  (`172.18.0.0/16`), IPv4 or IPv6.
  """

  @type entry :: {:inet.ip_address(), non_neg_integer}

  @doc "Whether the request's peer address is a trusted proxy."
  @spec trusted?(:inet.ip_address() | nil) :: boolean
  def trusted?(ip) when is_tuple(ip) do
    ip = unmap(ip)
    Enum.any?(entries!(), &covers?(&1, ip))
  end

  def trusted?(_ip), do: false

  @doc "The configured entries, parsed; raises on one that is not an address or a range."
  @spec entries!() :: [entry]
  def entries! do
    :ziwoas
    |> Application.get_env(:trusted_proxies, [])
    |> Enum.map(&parse!/1)
  end

  @spec parse!(String.t()) :: entry
  def parse!(entry) do
    case parse(String.trim(entry)) do
      {:ok, parsed} -> parsed
      :error -> raise ArgumentError, "trusted proxy #{inspect(entry)} is no address or CIDR range"
    end
  end

  defp parse(entry) do
    case String.split(entry, "/") do
      [address] ->
        with {:ok, ip} <- address(address), do: {:ok, {ip, bits(ip)}}

      [address, prefix] ->
        with {:ok, ip} <- address(address),
             max = bits(ip),
             {prefix, ""} when prefix in 0..max//1 <- Integer.parse(prefix) do
          {:ok, {ip, prefix}}
        else
          _invalid -> :error
        end

      _invalid ->
        :error
    end
  end

  defp address(address) do
    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, ip} -> {:ok, unmap(ip)}
      {:error, _reason} -> :error
    end
  end

  defp covers?({network, prefix}, ip) when tuple_size(network) == tuple_size(ip) do
    size = bits(ip)
    <<net::bitstring-size(^prefix), _rest::bitstring>> = binary(network, size)
    <<addr::bitstring-size(^prefix), _rest::bitstring>> = binary(ip, size)
    net == addr
  end

  defp covers?(_entry, _ip), do: false

  defp bits(ip) when tuple_size(ip) == 4, do: 32
  defp bits(ip) when tuple_size(ip) == 8, do: 128

  defp binary(ip, 32), do: ip |> Tuple.to_list() |> Enum.into(<<>>, &<<&1::8>>)
  defp binary(ip, 128), do: ip |> Tuple.to_list() |> Enum.into(<<>>, &<<&1::16>>)

  # An IPv4 peer on a dual-stack socket arrives as ::ffff:a.b.c.d.
  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}

  defp unmap(ip), do: ip
end
