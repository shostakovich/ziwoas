defmodule Ziwoas.FakeFritzBox do
  @moduledoc """
  A Fritz!Box with FRITZ!DECT 301 thermostats behind a `DectClient`: it answers
  `getdevicelistinfos` from its state, takes `sethkrtsoll` and tells the test each one as
  `{:sethkrtsoll, ain, param}`.
  """
  alias Ziwoas.Fritz.DectClient

  @session ~s(<?xml version="1.0"?><SessionInfo><SID>abc123def456abcd</SID><Challenge>deadbeef</Challenge></SessionInfo>)

  @doc """
  `thermostats` maps an AIN to `%{name:, tsoll:}` and optionally `present:`, `celsius:`,
  `battery:`, `battery_low:`, `txbusy:`, `window_open:` and `boost:`.
  """
  @spec start(map) :: {pid, DectClient.t()}
  def start(thermostats) do
    test = self()

    {:ok, box} =
      Agent.start_link(fn ->
        %{thermostats: thermostats, down: false, refuse: false, inval: false}
      end)

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {status, body} = answer(box, test, conn.request_path, conn.query_params)
      Plug.Conn.send_resp(conn, status, body)
    end

    {box, DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])}
  end

  @spec turn(pid, String.t(), integer) :: :ok
  def turn(box, ain, tsoll), do: put(box, ain, :tsoll, tsoll)

  @spec put(pid, String.t(), atom, term) :: :ok
  def put(box, ain, field, value),
    do: Agent.update(box, &put_in(&1, [:thermostats, ain, field], value))

  @spec tsoll(pid, String.t()) :: integer
  def tsoll(box, ain), do: Agent.get(box, &get_in(&1, [:thermostats, ain, :tsoll]))

  @doc """
  A box that is down answers nothing; one that refuses fails every `sethkrtsoll`; one set to
  `:inval` answers it with "inval", as for a device it does not know, and changes nothing.
  """
  @spec set(pid, :down | :refuse | :inval, boolean) :: :ok
  def set(box, flag, value), do: Agent.update(box, &Map.put(&1, flag, value))

  defp answer(box, test, path, params) do
    state = Agent.get(box, & &1)

    cond do
      state.down -> {503, ""}
      path == "/login_sid.lua" -> {200, @session}
      params["switchcmd"] == "getdevicelistinfos" -> {200, device_list(state.thermostats)}
      params["switchcmd"] == "sethkrtsoll" -> set_tsoll(box, test, state, params)
    end
  end

  defp set_tsoll(_box, _test, %{refuse: true}, _params), do: {500, ""}
  defp set_tsoll(_box, _test, %{inval: true}, _params), do: {200, "inval\n"}

  defp set_tsoll(box, test, _state, %{"ain" => ain, "param" => param}) do
    send(test, {:sethkrtsoll, ain, param})
    turn(box, ain, String.to_integer(param))
    {200, param <> "\n"}
  end

  defp device_list(thermostats) do
    devices =
      for {ain, t} <- thermostats do
        """
        <device identifier="#{ain}" functionbitmask="320" productname="FRITZ!DECT 301">
          <present>#{flag(t, :present, true)}</present>
          <txbusy>#{flag(t, :txbusy, false)}</txbusy>
          <name>#{t.name}</name>
          <battery>#{Map.get(t, :battery, 80)}</battery>
          <batterylow>#{flag(t, :battery_low, false)}</batterylow>
          <temperature><celsius>#{Map.get(t, :celsius, 205)}</celsius></temperature>
          <hkr>
            <tist>41</tist><tsoll>#{t.tsoll}</tsoll>
            <windowopenactiv>#{flag(t, :window_open, false)}</windowopenactiv>
            <boostactive>#{flag(t, :boost, false)}</boostactive>
          </hkr>
        </device>
        """
      end

    ~s(<devicelist version="1">#{devices}</devicelist>)
  end

  defp flag(thermostat, field, default),
    do: if(Map.get(thermostat, field, default), do: 1, else: 0)
end
