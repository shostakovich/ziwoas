defmodule Ziwoas.Govee.Lan do
  @moduledoc """
  The Govee LAN protocol. Commands are JSON datagrams to a lamp's port 4003; a
  scan goes to the multicast group 239.255.255.250:4001; lamps answer scans and
  `devStatus` on port 4002, where the bridge listens.

  `datagram/1` builds what to send (pure); `send_datagram/1` sends it from a
  throwaway UDP socket, one per command.
  """
  alias Ziwoas.Govee.Types

  @cmd_port 4003
  @scan_group ~c"239.255.255.250"
  @scan_port 4001

  def listen_port, do: 4002
  def scan_group, do: {239, 255, 255, 250}

  @type datagram :: %{host: String.t(), port: :inet.port_number(), data: String.t()}

  @doc """
  The datagram for a command: `{:turn, ip, on}`, `{:brightness, ip, value}`,
  `{:color, ip, %{r:, g:, b:}}`, `{:color_temp, ip, kelvin}`,
  `{:request_status, ip}` or `:discover`.
  """
  @spec datagram(tuple | :discover) :: datagram
  def datagram({:turn, ip, on}), do: command(ip, "turn", %{"value" => if(on, do: 1, else: 0)})
  def datagram({:brightness, ip, value}), do: command(ip, "brightness", %{"value" => value})
  def datagram({:request_status, ip}), do: command(ip, "devStatus", %{})

  def datagram({:color, ip, %{r: r, g: g, b: b}}),
    do:
      command(ip, "colorwc", %{
        "color" => %{"r" => r, "g" => g, "b" => b},
        "colorTemInKelvin" => 0
      })

  def datagram({:color_temp, ip, kelvin}),
    do:
      command(ip, "colorwc", %{
        "color" => %{"r" => 0, "g" => 0, "b" => 0},
        "colorTemInKelvin" => kelvin
      })

  def datagram(:discover) do
    %{
      host: List.to_string(@scan_group),
      port: @scan_port,
      data: encode("scan", %{"account_topic" => "reserve"})
    }
  end

  defp command(ip, cmd, data), do: %{host: ip, port: @cmd_port, data: encode(cmd, data)}

  defp encode(cmd, data), do: JSON.encode!(%{"msg" => %{"cmd" => cmd, "data" => data}})

  @doc "Sends one datagram from a fresh socket (multicast TTL 2, for the scan)."
  @spec send_datagram(datagram) :: :ok | {:error, term}
  def send_datagram(%{host: host, port: port, data: data}) do
    with {:ok, address} <- :inet.parse_address(String.to_charlist(host)),
         {:ok, socket} <- :gen_udp.open(0, [:binary, multicast_ttl: 2]) do
      try do
        :gen_udp.send(socket, address, port, data)
      after
        :gen_udp.close(socket)
      end
    end
  end

  # --- Replies --------------------------------------------------------------------

  @doc """
  A `devStatus` reply as `%{on:, brightness:, color_r:,
  color_g:, color_b:, color_temp_k:, sku:}`, or nil for anything else, including
  out-of-range values (never crashes the listener).
  """
  @spec parse_status(binary) :: map | nil
  def parse_status(payload) do
    with %{"onOff" => on_off} = data <- reply_data(payload),
         color = if(is_map(data["color"]), do: data["color"], else: %{}),
         {:ok, brightness} <- optional(data["brightness"], &Types.brightness/1),
         {:ok, r} <- optional(color["r"], &Types.rgb_component/1),
         {:ok, g} <- optional(color["g"], &Types.rgb_component/1),
         {:ok, b} <- optional(color["b"], &Types.rgb_component/1),
         {:ok, kelvin} <- optional(data["colorTemInKelvin"], &Types.kelvin/1),
         {:ok, sku} <- optional(data["sku"], &Types.string/1) do
      %{
        on: on_off == 1,
        brightness: brightness,
        color_r: r,
        color_g: g,
        color_b: b,
        color_temp_k: kelvin,
        sku: sku
      }
    else
      _ -> nil
    end
  end

  @doc "`%{ip:, mac:, sku:}` from a scan reply, else nil."
  @spec parse_scan(binary) :: map | nil
  def parse_scan(payload) do
    case reply_data(payload) do
      %{"ip" => ip, "device" => mac} = data
      when ip not in [nil, false] and mac not in [nil, false] ->
        %{ip: ip, mac: mac, sku: data["sku"]}

      _ ->
        nil
    end
  end

  defp reply_data(payload) do
    case JSON.decode(payload) do
      {:ok, %{"msg" => %{"data" => %{} = data}}} -> data
      _ -> nil
    end
  end

  defp optional(nil, _fun), do: {:ok, nil}
  defp optional(value, fun), do: fun.(value)

  @doc """
  A parsed status as store telemetry. Kelvin wins when positive, else the
  colour (when the lamp sent one).
  """
  @spec telemetry(map) :: map
  def telemetry(status) do
    telemetry = %{on: status.on, reachable: true}

    telemetry =
      if is_nil(status.brightness),
        do: telemetry,
        else: Map.put(telemetry, :brightness, status.brightness)

    cond do
      (status.color_temp_k || 0) > 0 ->
        Map.put(telemetry, :color_temp_k, status.color_temp_k)

      not is_nil(status.color_r) ->
        Map.put(telemetry, :color, %{r: status.color_r, g: status.color_g, b: status.color_b})

      true ->
        telemetry
    end
  end
end
