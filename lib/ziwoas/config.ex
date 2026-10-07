defmodule Ziwoas.Config do
  @moduledoc """
  The device configuration: `config/ziwoas.yml`. Raw YAML is checked and typed
  into structs at this boundary; nothing downstream sees a map from the file.

  `app_config/0` reads the file once per path (`:ziwoas, :config_path`, set
  from `ZIWOAS_CONFIG` in `config/runtime.exs`) and keeps it in
  `:persistent_term`; `reset/0` forgets it.
  """
  require Logger

  alias Ziwoas.Location
  alias Ziwoas.Plugs.{Plug, Roster}

  defmodule Error do
    defexception [:message]
  end

  defmodule Mqtt do
    @moduledoc false
    defstruct [:host, :port, :topic_prefix]

    @type t :: %__MODULE__{host: String.t(), port: :inet.port_number(), topic_prefix: String.t()}
  end

  defmodule FritzPoll do
    @moduledoc false
    defstruct [
      :active_interval_seconds,
      :idle_interval_seconds,
      :idle_threshold_w,
      :timeout_seconds
    ]
  end

  defmodule FritzBox do
    @moduledoc false
    defstruct [:host, :user, :password]
  end

  defmodule Switchbot do
    @moduledoc false
    defstruct [:token, :secret]
  end

  defmodule Sensor do
    @moduledoc "An air sensor: `type` is `:meter_pro_co2` (indoor) or `:outdoor_meter`."
    defstruct [:id, :name, :type, :room]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            type: :meter_pro_co2 | :outdoor_meter,
            room: String.t() | nil
          }
  end

  defmodule Trmnl do
    @moduledoc false
    defstruct [:energy_webhook_url, :sensors_webhook_url]
  end

  defmodule Solakon do
    @moduledoc false
    defstruct [:host, :port, :unit_id, :monitoring_enabled, :control_enabled]
  end

  defmodule Govee do
    @moduledoc false
    defstruct [:api_key, :lan_poll_seconds, :api_poll_seconds, :pending_window_seconds, :names]
  end

  @enforce_keys [:location, :mqtt, :plugs]
  defstruct [
    :location,
    :mqtt,
    :fritz_poll,
    :plugs,
    :fritz_box,
    :switchbot,
    :trmnl,
    :solakon,
    :govee,
    sensors: []
  ]

  @type t :: %__MODULE__{
          location: Location.t(),
          mqtt: %Mqtt{},
          fritz_poll: %FritzPoll{} | nil,
          plugs: [Plug.t()],
          fritz_box: %FritzBox{} | nil,
          switchbot: %Switchbot{} | nil,
          sensors: [Sensor.t()],
          trmnl: %Trmnl{},
          solakon: %Solakon{} | nil,
          govee: %Govee{} | nil
        }

  @id_regex ~r/\A[a-z0-9_]+\z/
  @roles %{"producer" => :producer, "consumer" => :consumer}
  @drivers %{"shelly" => :shelly, "fritz_dect" => :fritz_dect}
  @sensor_types %{"meter_pro_co2" => :meter_pro_co2, "outdoor_meter" => :outdoor_meter}
  @trmnl_keys ~w[energy_webhook_url sensors_webhook_url]
  @retired %{"timezone" => "location.timezone", "weather" => "location.lat / location.lon"}
  @obsolete %{
    "electricity_price_eur_per_kwh" => "the Strompreis list under PV > Wirtschaftlichkeit"
  }

  # --- Loading ---------------------------------------------------------------

  @doc "The configuration at the configured path, read once."
  @spec app_config() :: t
  def app_config do
    path = path()

    case :persistent_term.get({__MODULE__, path}, nil) do
      nil ->
        config = load!(path)
        :persistent_term.put({__MODULE__, path}, config)
        config

      config ->
        config
    end
  end

  @doc "Forgets every cached configuration."
  @spec reset() :: :ok
  def reset do
    for {{__MODULE__, _} = key, _} <- :persistent_term.get(), do: :persistent_term.erase(key)
    :ok
  end

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:ziwoas, :config_path)

  @spec load!(String.t()) :: t
  def load!(path) do
    if File.regular?(path),
      do: path |> parse_file() |> build!(),
      else: error!("config file not found")
  end

  @doc "Builds a configuration from YAML text (tests)."
  @spec from_yaml!(String.t()) :: t
  def from_yaml!(yaml), do: yaml |> parse_string() |> build!()

  @spec plug_roster(t) :: Roster.t()
  def plug_roster(%__MODULE__{plugs: plugs}), do: Roster.new(plugs)

  defp parse_file(path),
    do: parse(fn opts -> :yamerl_constr.file(String.to_charlist(path), opts) end)

  defp parse_string(yaml), do: parse(fn opts -> :yamerl_constr.string(yaml, opts) end)

  # YAML 1.1: unquoted yes/no/on/off (and y/n) are booleans.
  @yaml_opts [
    :str_node_as_binary,
    {:map_node_format, :map},
    {:node_mods, [:yamerl_node_bool_ext]}
  ]

  defp parse(fun) do
    case fun.(@yaml_opts) do
      [document | _] -> document
      [] -> nil
    end
  catch
    {:yamerl_exception, _errors} -> error!("config file is not valid YAML")
  end

  defp build!(raw) when is_map(raw) do
    reject_retired_keys!(raw)
    warn_obsolete_keys(raw)

    location = build_location(raw["location"])
    mqtt = build_mqtt(raw["mqtt"])
    fritz_poll = build_fritz_poll(raw["fritz_poll"])
    fritz_box = build_fritz_box(raw["fritz_box"])
    plugs = build_plugs(raw["plugs"])
    switchbot = build_switchbot(raw["switchbot"])
    sensors = build_sensors(raw["sensors"])
    trmnl = build_trmnl(raw["trmnl"])
    solakon = build_solakon(raw["solakon"])
    govee = build_govee(raw["govee"])

    fritz? = Enum.any?(plugs, &(&1.driver == :fritz_dect))

    if fritz? and is_nil(fritz_box),
      do: error!("fritz_box config required when using driver: fritz_dect")

    if fritz? and is_nil(fritz_poll),
      do: error!("fritz_poll config required when using driver: fritz_dect")

    %__MODULE__{
      location: location,
      mqtt: mqtt,
      fritz_poll: fritz_poll,
      plugs: plugs,
      fritz_box: fritz_box,
      switchbot: switchbot,
      sensors: sensors,
      trmnl: trmnl,
      solakon: solakon,
      govee: govee
    }
  end

  defp build!(_raw), do: error!("config root must be a mapping")

  # --- Sections ----------------------------------------------------------------

  defp reject_retired_keys!(raw) do
    for {old, new} <- @retired, Map.has_key?(raw, old), do: error!("'#{old}' has moved to #{new}")
  end

  defp warn_obsolete_keys(raw) do
    for {old, new} <- @obsolete, Map.has_key?(raw, old) do
      Logger.warning("config: '#{old}' is no longer read — it moved to #{new}. Remove the key.")
    end

    if Map.has_key?(raw, "migration"),
      do:
        Logger.warning(
          "config: the 'migration' block is no longer read — Phoenix runs every task. Remove it."
        )
  end

  defp build_location(h) do
    h = require_map(h, "location")
    tz = require_string(h["timezone"], "location.timezone")

    unless valid_zone?(tz),
      do: error!("location.timezone '#{tz}' is not a valid IANA timezone")

    Location.new(tz, coordinates(h))
  end

  defp valid_zone?(tz), do: match?({:ok, _}, DateTime.now(tz))

  defp coordinates(h) do
    if nil?(h["lat"]) and nil?(h["lon"]) do
      []
    else
      lat = require_coordinate(h["lat"], "location.lat")
      lon = require_coordinate(h["lon"], "location.lon")
      unless lat >= -90 and lat <= 90, do: error!("location.lat must be between -90 and 90")
      unless lon >= -180 and lon <= 180, do: error!("location.lon must be between -180 and 180")
      [lat: lat, lon: lon]
    end
  end

  defp build_mqtt(h) do
    if nil?(h), do: error!("mqtt config is required")
    h = require_map(h, "mqtt")

    %Mqtt{
      host: require_string(h["host"], "mqtt.host"),
      port: require_number(to_integer(h["port"]), "mqtt.port"),
      topic_prefix: require_string(h["topic_prefix"], "mqtt.topic_prefix")
    }
  end

  defp build_fritz_poll(h) do
    if nil?(h) do
      nil
    else
      h = require_map(h, "fritz_poll")

      %FritzPoll{
        active_interval_seconds:
          require_number(h["active_interval_seconds"], "fritz_poll.active_interval_seconds"),
        idle_interval_seconds:
          require_number(h["idle_interval_seconds"], "fritz_poll.idle_interval_seconds"),
        idle_threshold_w:
          require_number(to_float(h["idle_threshold_w"]), "fritz_poll.idle_threshold_w",
            allow_zero: true
          ),
        timeout_seconds: require_number(h["timeout_seconds"], "fritz_poll.timeout_seconds")
      }
    end
  end

  defp build_fritz_box(h) do
    if nil?(h) do
      nil
    else
      h = require_map(h, "fritz_box")

      %FritzBox{
        host: require_string(h["host"], "fritz_box.host"),
        user: require_string(h["user"], "fritz_box.user"),
        password: require_string(h["password"], "fritz_box.password")
      }
    end
  end

  defp build_plugs(list) when is_list(list) do
    plugs =
      list
      |> Enum.with_index()
      |> Enum.reduce([], fn {h, i}, built ->
        [build_plug(h, i, Enum.map(built, & &1.id)) | built]
      end)
      |> Enum.reverse()

    if plugs != [] and not Enum.any?(plugs, &(&1.role == :producer)),
      do: error!("config must include at least one plug with role: producer")

    plugs
  end

  defp build_plugs(_), do: error!("plugs must be a list")

  defp build_plug(h, i, existing_ids) do
    unless is_map(h), do: error!("plugs[#{i}] must be a mapping")

    id = plug_id(h, i, existing_ids)
    role = plug_role(h, i, id)
    driver = plug_driver(h, id)
    name = require_string(h["name"], "plugs[#{i}].name")
    switchable = plug_switchable(h, i, id, role)
    room = if nil?(h["room"]), do: nil, else: require_string(h["room"], "plugs[#{i}].room")
    ain = plug_ain(h, i, driver)

    %Plug{
      id: id,
      name: name,
      role: role,
      driver: driver,
      ain: ain,
      room: room,
      switchable: switchable
    }
  end

  defp plug_id(h, i, existing_ids) do
    id = require_string(h["id"], "plugs[#{i}].id")

    unless Regex.match?(@id_regex, id),
      do: error!("plug id '#{id}' must match #{Regex.source(@id_regex)}")

    if id in existing_ids, do: error!("duplicate plug id '#{id}'")

    id
  end

  defp plug_role(h, i, id) do
    role = Map.get(@roles, require_string(h["role"], "plugs[#{i}].role"))
    unless role, do: error!("plug '#{id}' role must be one of [:producer, :consumer]")
    role
  end

  defp plug_driver(h, id) do
    driver = Map.get(@drivers, to_text(if nil?(h["driver"]), do: "shelly", else: h["driver"]))
    unless driver, do: error!("plug '#{id}' driver must be one of [:shelly, :fritz_dect]")
    driver
  end

  defp plug_switchable(h, i, id, role) do
    switchable = Map.get(h, "switchable", false)

    unless is_boolean(switchable), do: error!("plugs[#{i}].switchable must be true or false")

    if switchable and role == :producer,
      do: error!("plug '#{id}' with role: producer cannot be switchable")

    switchable
  end

  defp plug_ain(h, i, :shelly) do
    if present_value?(h["ain"]), do: error!("plugs[#{i}].ain must not be set for driver: shelly")
    nil
  end

  defp plug_ain(h, i, :fritz_dect) do
    ain = h["ain"]

    if nil?(ain) or to_text(ain) == "",
      do: error!("plugs[#{i}].ain is required for driver: fritz_dect")

    to_text(ain)
  end

  defp build_switchbot(h) do
    if nil?(h) do
      nil
    else
      h = require_map(h, "switchbot")

      %Switchbot{
        token: require_string(h["token"], "switchbot.token"),
        secret: require_string(h["secret"], "switchbot.secret")
      }
    end
  end

  defp build_sensors(list) do
    cond do
      nil?(list) ->
        []

      is_list(list) ->
        list |> Enum.with_index() |> Enum.reduce([], &build_sensor/2) |> Enum.reverse()

      true ->
        error!("sensors must be a list")
    end
  end

  defp build_sensor({h, i}, built) do
    unless is_map(h), do: error!("sensors[#{i}] must be a mapping")

    id = require_string(h["id"], "sensors[#{i}].id")
    name = require_string(h["name"], "sensors[#{i}].name")
    type = Map.get(@sensor_types, require_string(h["type"], "sensors[#{i}].type"))

    unless type,
      do: error!("sensors[#{i}].type must be one of [:meter_pro_co2, :outdoor_meter]")

    if Enum.any?(built, &(&1.id == id)), do: error!("duplicate sensor id '#{id}'")
    room = if nil?(h["room"]), do: nil, else: require_string(h["room"], "sensors[#{i}].room")

    [%Sensor{id: id, name: name, type: type, room: room} | built]
  end

  defp build_trmnl(h) do
    if nil?(h) do
      %Trmnl{}
    else
      h = require_map(h, "trmnl")
      unknown = Map.keys(h) -- @trmnl_keys
      if unknown != [], do: error!("trmnl unknown keys: #{Enum.join(unknown, ", ")}")

      %Trmnl{
        energy_webhook_url: optional_string(h["energy_webhook_url"], "trmnl.energy_webhook_url"),
        sensors_webhook_url:
          optional_string(h["sensors_webhook_url"], "trmnl.sensors_webhook_url")
      }
    end
  end

  defp build_solakon(h) do
    if nil?(h) do
      nil
    else
      h = require_map(h, "solakon")

      %Solakon{
        host: require_string(h["host"], "solakon.host"),
        port: require_number(to_integer(default(h["port"], 502)), "solakon.port"),
        unit_id: require_number(to_integer(default(h["unit_id"], 1)), "solakon.unit_id"),
        # `enabled` is the legacy spelling of `monitoring_enabled`.
        monitoring_enabled: solakon_boolean(h, "monitoring_enabled", true, "enabled"),
        control_enabled: solakon_boolean(h, "control_enabled", false, nil)
      }
    end
  end

  defp solakon_boolean(h, key, default, legacy) do
    cond do
      Map.has_key?(h, key) -> require_boolean(h[key], "solakon.#{key}")
      legacy && Map.has_key?(h, legacy) -> require_boolean(h[legacy], "solakon.#{legacy}")
      true -> default
    end
  end

  defp build_govee(h) do
    if nil?(h) do
      nil
    else
      h = require_map(h, "govee")

      names =
        h["devices"]
        |> list()
        |> Enum.reduce(%{}, fn device, acc ->
          key = require_string(device["key"], "govee.devices[].key")
          Map.put(acc, key, %{name: to_text(device["name"])})
        end)

      %Govee{
        api_key: to_text(h["api_key"]),
        lan_poll_seconds: govee_seconds(h, "lan_poll_seconds", 8),
        api_poll_seconds: govee_seconds(h, "api_poll_seconds", 180),
        pending_window_seconds: govee_seconds(h, "pending_window_seconds", 5),
        names: names
      }
    end
  end

  defp govee_seconds(h, key, fallback),
    do: require_number(to_integer(default(h[key], fallback)), "govee.#{key}")

  # --- Checks ------------------------------------------------------------------

  defp require_map(v, key), do: if(is_map(v), do: v, else: error!("#{key} must be a mapping"))

  defp require_string(v, key) do
    text = if nil?(v), do: "", else: to_text(v)
    if text == "", do: error!("#{key} is required"), else: text
  end

  defp optional_string(v, key) do
    cond do
      nil?(v) -> nil
      is_binary(v) -> v
      true -> error!("#{key} must be a string")
    end
  end

  defp require_boolean(v, _key) when is_boolean(v), do: v
  defp require_boolean(_v, key), do: error!("#{key} must be true or false")

  defp require_number(v, key, opts \\ [])

  defp require_number(v, key, opts) when is_number(v) do
    too_small = if opts[:allow_zero], do: v < 0, else: v <= 0
    if too_small, do: error!("#{key} must be > 0"), else: v
  end

  defp require_number(_v, key, _opts), do: error!("#{key} must be a number")

  defp require_coordinate(v, key) do
    cond do
      nil?(v) or v == "" -> error!("#{key} must be a number")
      is_number(v) -> :erlang.float(v)
      is_binary(v) -> parse_float(String.trim(v)) || error!("#{key} must be a number")
      true -> error!("#{key} must be a number")
    end
  end

  defp parse_float(text) do
    case Float.parse(text) do
      {value, ""} -> value
      _ -> nil
    end
  end

  # --- YAML scalars ------------------------------------------------------------

  defp nil?(v), do: v in [nil, :null]
  defp default(v, fallback), do: if(nil?(v) or v == false, do: fallback, else: v)
  defp present_value?(v), do: not nil?(v) and v != false

  defp list(v) do
    cond do
      nil?(v) -> []
      is_list(v) -> v
      true -> [v]
    end
  end

  defp to_text(v) when is_binary(v), do: v
  defp to_text(v) when is_integer(v), do: Integer.to_string(v)
  defp to_text(v) when is_float(v), do: Float.to_string(v)
  defp to_text(v) when is_boolean(v), do: Atom.to_string(v)
  defp to_text(v) when v in [nil, :null], do: ""
  defp to_text(v), do: inspect(v)

  defp to_integer(v) when is_integer(v), do: v

  defp to_integer(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp to_integer(_v), do: nil

  defp to_float(v) when is_number(v), do: v * 1.0
  defp to_float(v) when is_binary(v), do: parse_float(String.trim(v))
  defp to_float(_v), do: nil

  defp error!(message), do: raise(Error, message)
end
