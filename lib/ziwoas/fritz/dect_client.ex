defmodule Ziwoas.Fritz.DectClient do
  @moduledoc false
  alias Ziwoas.Fritz.Thermostat

  @derive {Inspect, except: [:password, :sid]}
  @enforce_keys [:host, :user, :password]
  defstruct [:host, :user, :password, :sid, timeout_s: 2, req: []]

  @type t :: %__MODULE__{}
  @type reading :: %{apower_w: float, aenergy_wh: float}

  @type reason ::
          {:http_status, pos_integer}
          | :forbidden_after_reauth
          | :blank_response
          | {:unexpected_response, String.t()}
          | {:auth_status, pos_integer}
          | :no_challenge
          | :auth_failed
          | :invalid_device_list
          | :deadline_exceeded
          | Exception.t()

  @no_session "0000000000000000"
  @radiator_controller 0x40
  @tsoll_off 253
  @tsoll_on 254

  @spec new(keyword) :: t
  def new(opts), do: struct!(__MODULE__, opts)

  @spec fetch(t, String.t()) :: {:ok, reading, t} | {:error, reason, t}
  def fetch(%__MODULE__{} = client, ain) do
    with {:ok, client} <- ensure_session(client, :infinity),
         {:ok, power_mw, client} <- fetch_value(client, ain, "getswitchpower"),
         {:ok, energy_wh, client} <- fetch_value(client, ain, "getswitchenergy") do
      {:ok, %{apower_w: power_mw / 1000.0, aenergy_wh: energy_wh * 1.0}, client}
    end
  end

  @doc "Every radiator thermostat the box knows; other devices are left out."
  @spec thermostats(t) :: {:ok, [Thermostat.t()], t} | {:error, reason, t}
  def thermostats(%__MODULE__{} = client) do
    with {:ok, client} <- ensure_session(client, :infinity),
         {:ok, body, client} <-
           command(client, [{"switchcmd", "getdevicelistinfos"}], :infinity) do
      thermostats_in(body, client)
    end
  end

  defp thermostats_in(body, client) do
    case device_list(body) do
      {:ok, devices} ->
        thermostats =
          for device <- devices,
              radiator?(device),
              ain = attribute(device, ~c"identifier"),
              do: thermostat(device, ain)

        {:ok, thermostats, client}

      :error ->
        {:error, :invalid_device_list, client}
    end
  end

  @doc """
  Heats to a temperature (8–28 °C in half degrees) or switches the thermostat off.

  With `deadline:` (monotonic milliseconds) no request is sent, login included, unless its
  whole timeout still ends before the deadline.
  """
  @spec set_target(t, String.t(), {:heat, number} | :off, keyword) ::
          {:ok, t} | {:error, reason, t}
  def set_target(%__MODULE__{} = client, ain, target, opts \\ []) do
    tsoll = tsoll(target)
    params = [{"switchcmd", "sethkrtsoll"}, {"ain", ain}, {"param", tsoll}]
    deadline = Keyword.get(opts, :deadline, :infinity)

    with {:ok, client} <- ensure_session(client, deadline),
         {:ok, body, client} <- command(client, params, deadline),
         do: confirmed(body, tsoll, client)
  end

  # The box confirms by answering the value it set.
  defp confirmed(body, tsoll, client) do
    case value(body, client) do
      {:ok, ^tsoll, client} -> {:ok, client}
      {:ok, _other, client} -> {:error, {:unexpected_response, String.trim(body)}, client}
      error -> error
    end
  end

  defp tsoll(:off), do: @tsoll_off
  defp tsoll({:heat, celsius}) when celsius >= 8 and celsius <= 28, do: round(celsius * 2)

  defp ensure_session(%{sid: nil} = client, deadline), do: authenticate(client, deadline)
  defp ensure_session(client, _deadline), do: {:ok, client}

  defp fetch_value(client, ain, cmd) do
    with {:ok, body, client} <- command(client, [{"switchcmd", cmd}, {"ain", ain}], :infinity),
         do: value(body, client)
  end

  defp value(body, client) do
    body = String.trim(body)
    if body == "", do: {:error, :blank_response, client}, else: integer(body, client)
  end

  defp command(client, params, deadline) do
    with {:ok, response, client} <- with_reauth(client, params, deadline) do
      if response.status in 200..299,
        do: {:ok, to_string(response.body), client},
        else: {:error, {:http_status, response.status}, client}
    end
  end

  # The box answers "inval" for a device it does not know.
  defp integer(body, client) do
    case Integer.parse(body) do
      {value, ""} -> {:ok, value, client}
      _ -> {:error, {:unexpected_response, body}, client}
    end
  end

  defp with_reauth(client, params, deadline) do
    case homeauto(client, params, deadline) do
      {:ok, %{status: 403}} -> reauth(client, params, deadline)
      {:ok, response} -> {:ok, response, client}
      {:error, reason} -> {:error, reason, client}
    end
  end

  defp reauth(client, params, deadline) do
    with {:ok, client} <- authenticate(%{client | sid: nil}, deadline) do
      case homeauto(client, params, deadline) do
        {:ok, %{status: 403}} -> {:error, :forbidden_after_reauth, client}
        {:ok, response} -> {:ok, response, client}
        {:error, reason} -> {:error, reason, client}
      end
    end
  end

  defp homeauto(client, params, deadline),
    do: get(client, "/webservices/homeautoswitch.lua", params ++ [{"sid", client.sid}], deadline)

  defp authenticate(client, deadline) do
    with {:ok, response} <- get(client, "/login_sid.lua", [], deadline),
         :ok <- auth_status(response),
         {:ok, challenge} <- challenge(response.body),
         {:ok, response} <-
           get(
             client,
             "/login_sid.lua",
             [{"username", client.user}, {"response", response(challenge, client.password)}],
             deadline
           ),
         :ok <- auth_status(response),
         {:ok, sid} <- session_id(response.body) do
      {:ok, %{client | sid: sid}}
    else
      {:error, reason} -> {:error, reason, %{client | sid: nil}}
    end
  end

  defp auth_status(%{status: status}) when status in 200..299, do: :ok
  defp auth_status(%{status: status}), do: {:error, {:auth_status, status}}

  defp challenge(body) do
    case xml_text(body, ~c"/SessionInfo/Challenge") do
      nil -> {:error, :no_challenge}
      challenge -> {:ok, challenge}
    end
  end

  defp session_id(body) do
    case xml_text(body, ~c"/SessionInfo/SID") do
      sid when sid in [nil, @no_session] -> {:error, :auth_failed}
      sid -> {:ok, sid}
    end
  end

  @doc "The login response to a challenge: PBKDF2 for `2$…`, else MD5 over UTF-16LE."
  @spec response(String.t(), String.t()) :: String.t()
  def response("2$" <> _ = challenge, password) do
    ["2", iter1, salt1, iter2, salt2] = String.split(challenge, "$")
    hash1 = pbkdf2(password, Base.decode16!(salt1, case: :mixed), String.to_integer(iter1))
    hash2 = pbkdf2(hash1, Base.decode16!(salt2, case: :mixed), String.to_integer(iter2))
    "#{salt2}$#{Base.encode16(hash2, case: :lower)}"
  end

  def response(challenge, password) do
    utf16 = :unicode.characters_to_binary("#{challenge}-#{password}", :utf8, {:utf16, :little})
    "#{challenge}-#{Base.encode16(:crypto.hash(:md5, utf16), case: :lower)}"
  end

  defp pbkdf2(secret, salt, iterations),
    do: :crypto.pbkdf2_hmac(:sha256, secret, salt, iterations, 32)

  defp xml_text(body, path) do
    case parse_xml(body) do
      {:ok, doc} -> text_at(doc, path)
      :error -> nil
    end
  end

  # xmerl exits, raises or throws on a body that is not XML.
  defp parse_xml(body) do
    {doc, _rest} = body |> to_string() |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)
    {:ok, doc}
  catch
    _kind, _reason -> :error
  end

  defp text_at(node, path) do
    case :xmerl_xpath.string(path ++ ~c"/text()", node) do
      [{:xmlText, _, _, _, value, _} | _] ->
        value |> List.to_string() |> String.trim() |> nil_if_blank()

      _ ->
        nil
    end
  end

  defp device_list(body) do
    case parse_xml(body) do
      {:ok, {:xmlElement, :devicelist, _, _, _, _, _, _, _, _, _, _} = doc} ->
        {:ok, :xmerl_xpath.string(~c"/devicelist/device", doc)}

      _ ->
        :error
    end
  end

  defp radiator?(device) do
    case Integer.parse(attribute(device, ~c"functionbitmask") || "") do
      {mask, ""} -> Bitwise.band(mask, @radiator_controller) != 0
      _ -> false
    end
  end

  defp thermostat(device, ain) do
    %Thermostat{
      key: Thermostat.key(ain),
      ain: ain,
      name: text_at(device, ~c"name") || ain,
      present: text_at(device, ~c"present") == "1",
      measured_c: measured_c(device),
      target: target(int_at(device, ~c"hkr/tsoll")),
      battery_pct: int_at(device, ~c"battery"),
      battery_low: text_at(device, ~c"batterylow") == "1",
      busy:
        Enum.any?(~w(txbusy hkr/windowopenactiv hkr/boostactive)c, &(text_at(device, &1) == "1"))
    }
  end

  defp measured_c(device) do
    case {int_at(device, ~c"temperature/celsius"), int_at(device, ~c"hkr/tist")} do
      {tenths, _} when is_integer(tenths) -> tenths / 10
      {nil, halves} when is_integer(halves) -> halves / 2
      {nil, nil} -> nil
    end
  end

  defp target(@tsoll_off), do: :off
  defp target(@tsoll_on), do: :on
  defp target(halves) when halves in 16..56, do: {:heat, halves / 2}
  defp target(_tsoll), do: nil

  defp int_at(node, path) do
    with text when is_binary(text) <- text_at(node, path),
         {value, ""} <- Integer.parse(text),
         do: value,
         else: (_ -> nil)
  end

  defp attribute(device, name) do
    case :xmerl_xpath.string(~c"@" ++ name, device) do
      [{:xmlAttribute, _, _, _, _, _, _, _, value, _} | _] -> List.to_string(value)
      _ -> nil
    end
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(text), do: text

  defp get(client, path, params, deadline) do
    if fits?(client, deadline),
      do: request(client, path, params),
      else: {:error, :deadline_exceeded}
  end

  defp fits?(_client, :infinity), do: true

  defp fits?(client, deadline),
    do: System.monotonic_time(:millisecond) + client.timeout_s * 1000 <= deadline

  defp request(client, path, params) do
    __MODULE__
    |> Ziwoas.Http.new(
      Keyword.merge(
        [
          url: "http://#{client.host}#{path}",
          params: params,
          retry: false,
          redirect: false,
          connect_options: [timeout: client.timeout_s * 1000],
          receive_timeout: client.timeout_s * 1000
        ],
        client.req
      )
    )
    |> Req.get()
  end
end
