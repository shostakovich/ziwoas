defmodule Ziwoas.Fritz.DectClient do
  @moduledoc """
  Power (mW) and energy (Wh) of a Fritz!DECT plug via the Fritz!Box's AHA HTTP
  interface, with the challenge-response login of `login_sid.lua`. A session id is
  reused until a 403 asks for a new login (once).

  The login asks without `version`, so the box offers an MD5 challenge
  (`<challenge>-<md5 of UTF-16LE "challenge-password">`); a PBKDF2 challenge
  (`2$iter1$salt1$iter2$salt2`, Fritz!OS 7.24+) is answered too, so a box that stops
  offering MD5 still logs in.

  The client is a struct; `fetch/2` returns it with the session it ended on.
  """
  @enforce_keys [:host, :user, :password]
  defstruct [:host, :user, :password, :sid, timeout_s: 2, req: []]

  @type t :: %__MODULE__{}
  @type reading :: %{apower_w: float, aenergy_wh: float}

  @typedoc "Why a fetch failed; a network failure is Req's exception."
  @type reason ::
          {:http_status, pos_integer}
          | :forbidden_after_reauth
          | :blank_response
          | {:unexpected_response, String.t()}
          | {:auth_status, pos_integer}
          | :no_challenge
          | :auth_failed
          | Exception.t()

  @no_session "0000000000000000"

  @doc "`req` are extra Req options (`Ziwoas.Http`); tests pass `plug:`."
  @spec new(keyword) :: t
  def new(opts), do: struct!(__MODULE__, opts)

  @doc "The plug's reading (`ain`), or `{:error, reason, client}`."
  @spec fetch(t, String.t()) :: {:ok, reading, t} | {:error, reason, t}
  def fetch(%__MODULE__{} = client, ain) do
    with {:ok, client} <- ensure_session(client),
         {:ok, power_mw, client} <- fetch_value(client, ain, "getswitchpower"),
         {:ok, energy_wh, client} <- fetch_value(client, ain, "getswitchenergy") do
      {:ok, %{apower_w: power_mw / 1000.0, aenergy_wh: energy_wh * 1.0}, client}
    end
  end

  defp ensure_session(%{sid: nil} = client), do: authenticate(client)
  defp ensure_session(client), do: {:ok, client}

  defp fetch_value(client, ain, cmd) do
    with {:ok, response, client} <- with_reauth(client, ain, cmd) do
      body = response.body |> to_string() |> String.trim()

      cond do
        response.status not in 200..299 -> {:error, {:http_status, response.status}, client}
        body == "" -> {:error, :blank_response, client}
        true -> integer(body, client)
      end
    end
  end

  # The box answers "inval" for a plug it does not know.
  defp integer(body, client) do
    case Integer.parse(body) do
      {value, ""} -> {:ok, value, client}
      _ -> {:error, {:unexpected_response, body}, client}
    end
  end

  defp with_reauth(client, ain, cmd) do
    case homeauto(client, ain, cmd) do
      {:ok, %{status: 403}} -> reauth(client, ain, cmd)
      {:ok, response} -> {:ok, response, client}
      {:error, reason} -> {:error, reason, client}
    end
  end

  defp reauth(client, ain, cmd) do
    with {:ok, client} <- authenticate(%{client | sid: nil}) do
      case homeauto(client, ain, cmd) do
        {:ok, %{status: 403}} -> {:error, :forbidden_after_reauth, client}
        {:ok, response} -> {:ok, response, client}
        {:error, reason} -> {:error, reason, client}
      end
    end
  end

  defp homeauto(client, ain, cmd),
    do:
      get(client, "/webservices/homeautoswitch.lua", [
        {"switchcmd", cmd},
        {"ain", ain},
        {"sid", client.sid}
      ])

  defp authenticate(client) do
    with {:ok, response} <- get(client, "/login_sid.lua", []),
         :ok <- auth_status(response),
         {:ok, challenge} <- challenge(response.body),
         {:ok, response} <-
           get(client, "/login_sid.lua", [
             {"username", client.user},
             {"response", response(challenge, client.password)}
           ]),
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

  # xmerl exits on a body that is not XML; that body has no text at the path.
  defp xml_text(body, path) do
    {doc, _rest} = body |> to_string() |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)

    case :xmerl_xpath.string(path ++ ~c"/text()", doc) do
      [{:xmlText, _, _, _, value, _} | _] -> value |> List.to_string() |> nil_if_blank()
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(text), do: text

  defp get(client, path, params) do
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
