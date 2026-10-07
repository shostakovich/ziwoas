defmodule Ziwoas.Govee.Messages do
  @moduledoc """
  Rails' `Govees::Messages`: the typed MQTT wire contracts between the Govee bridge
  and the subscriber. Parsing a raw (JSON-decoded) map returns `{:ok, struct-like
  map}` or `:error` where dry-struct raised; `*_wire/1` give the canonical wire
  object as an ordered pair list for `Ziwoas.RubyJSON`.

  A parsed state is a map holding only the keys the message had (dry-struct's
  `attribute?`): `:on` and `:reachable` always, `:brightness`, `:color`
  (`%{r:, g:, b:}`), `:color_temp_k`, `:zone_states` (string keys) when given.
  """
  import Bitwise

  alias Ziwoas.Govee.Types
  alias Ziwoas.RubyNumeric

  # --- State (govees/<key>/state) ---------------------------------------------

  @doc "`Messages::State.from_hash`: nil values are dropped, so defaults apply."
  @spec state(map) :: {:ok, map} | :error
  def state(hash) when is_map(hash) do
    hash = present(hash)

    with {:ok, on} <- default(hash, "on", false, &Types.bool/1),
         {:ok, reachable} <- default(hash, "reachable", true, &Types.bool/1),
         {:ok, state} <-
           optional(
             %{on: on, reachable: reachable},
             hash,
             "brightness",
             :brightness,
             &Types.brightness/1
           ),
         {:ok, state} <- optional(state, hash, "color", :color, &rgb/1),
         {:ok, state} <- optional(state, hash, "color_temp_k", :color_temp_k, &Types.kelvin/1) do
      optional(state, hash, "zone_states", :zone_states, &zone_states/1)
    end
  end

  def state(_hash), do: :error

  @doc "`Messages::State#to_wire`."
  @spec state_wire(map) :: [{String.t(), term}]
  def state_wire(state) do
    [{"on", state.on}, {"reachable", state.reachable}] ++
      for(
        {key, wire} <- [
          brightness: "brightness",
          color: "color",
          color_temp_k: "color_temp_k",
          zone_states: "zone_states"
        ],
        Map.has_key?(state, key),
        do: {wire, wire_value(key, state[key])}
      )
  end

  defp wire_value(:color, color), do: rgb_wire(color)
  defp wire_value(:zone_states, zones) when zones == %{}, do: %{}
  defp wire_value(:zone_states, zones), do: Enum.to_list(zones)
  defp wire_value(_key, value), do: value

  defp rgb_wire(%{r: r, g: g, b: b}), do: [{"r", r}, {"g", g}, {"b", b}]

  # --- Config (govees/<key>/config) -------------------------------------------

  @doc "`Messages::Config.from_hash`."
  @spec config(map) :: {:ok, map} | :error
  def config(hash) when is_map(hash) do
    hash = present(hash)

    with {:ok, sku} <- default(hash, "sku", "", &Types.string/1),
         {:ok, name} <- default(hash, "name", "", &Types.string/1),
         {:ok, color} <- default(hash, "supports_color", false, &Types.bool/1),
         {:ok, color_temp} <- default(hash, "supports_color_temp", false, &Types.bool/1),
         {:ok, min_k} <- default(hash, "color_temp_min_k", nil, &Types.optional_integer/1),
         {:ok, max_k} <- default(hash, "color_temp_max_k", nil, &Types.optional_integer/1),
         {:ok, zones} <- default(hash, "zones", [], &Types.list_of(&1, fn v -> Types.name(v) end)),
         {:ok, scenes} <-
           default(hash, "scenes", [], &Types.list_of(&1, fn v -> Types.name(v) end)) do
      {:ok,
       %{
         sku: sku,
         name: name,
         supports_color: color,
         supports_color_temp: color_temp,
         color_temp_min_k: min_k,
         color_temp_max_k: max_k,
         zones: zones,
         scenes: scenes
       }}
    end
  end

  def config(_hash), do: :error

  @doc "`Messages::Config#to_wire` of a parsed config or a `Ziwoas.Govee.Device`."
  @spec config_wire(map) :: [{String.t(), term}]
  def config_wire(config) do
    [
      {"sku", config.sku},
      {"name", config.name},
      {"supports_color", config.supports_color},
      {"supports_color_temp", config.supports_color_temp},
      {"color_temp_min_k", config.color_temp_min_k},
      {"color_temp_max_k", config.color_temp_max_k},
      {"zones", config.zones},
      {"scenes", config.scenes}
    ]
  end

  # --- DeviceState (Platform API capabilities) -----------------------------------

  @doc """
  `Messages::DeviceState.from_capabilities(map, zone_keys:).to_telemetry`: an
  unreachable lamp is never on, whatever the cloud remembers.
  """
  @spec device_telemetry(map, [String.t()]) :: {:ok, map} | :error
  def device_telemetry(map, zone_keys) do
    online = Map.get(map, "online", true)
    reachable = online === true or online == 1

    telemetry = %{
      on: reachable and RubyNumeric.to_i(map["powerSwitch"]) == 1,
      reachable: reachable
    }

    rgb = RubyNumeric.to_i(map["colorRgb"])

    with {:ok, telemetry} <-
           optional(telemetry, map, "brightness", :brightness, &Types.brightness/1),
         {:ok, telemetry} <- color_or_kelvin(telemetry, map, rgb) do
      zones =
        for zone <- zone_keys,
            (value = map[zone]) not in [nil, ""],
            into: %{},
            do: {zone, RubyNumeric.to_i(value) == 1}

      {:ok, if(zones == %{}, do: telemetry, else: Map.put(telemetry, :zone_states, zones))}
    end
  end

  defp color_or_kelvin(telemetry, _map, rgb) when rgb > 0,
    do:
      {:ok,
       Map.put(telemetry, :color, %{
         r: rgb >>> 16 &&& 0xFF,
         g: rgb >>> 8 &&& 0xFF,
         b: rgb &&& 0xFF
       })}

  defp color_or_kelvin(telemetry, map, _rgb) do
    if RubyNumeric.to_i(map["colorTemperatureK"]) > 0,
      do: optional(telemetry, map, "colorTemperatureK", :color_temp_k, &Types.kelvin/1),
      else: {:ok, telemetry}
  end

  # --- Set verbs (govees/<key>/set) -----------------------------------------------

  @doc """
  `Messages::Set.parse`: one verb, or `{:ok, nil}` for an unknown one. Verbs:
  `{:power, on}`, `{:brightness, value}`, `{:color, rgb}`, `{:color_temp, kelvin}`,
  `{:zone, name, on}`, `{:scene, name}`.
  """
  @spec set(map) :: {:ok, tuple | nil} | :error
  def set(hash) when is_map(hash) do
    hash = Map.new(hash, fn {key, value} -> {to_string(key), value} end)

    cond do
      Map.has_key?(hash, "power") ->
        wrap(Types.bool(hash["power"]), &{:power, &1})

      Map.has_key?(hash, "brightness") ->
        wrap(Types.brightness(hash["brightness"]), &{:brightness, &1})

      Map.has_key?(hash, "color") ->
        wrap(rgb(hash["color"]), &{:color, &1})

      Map.has_key?(hash, "color_temp_k") ->
        wrap(Types.kelvin(hash["color_temp_k"]), &{:color_temp, &1})

      Map.has_key?(hash, "zone") ->
        zone(hash["zone"])

      Map.has_key?(hash, "scene") ->
        wrap(Types.name(hash["scene"]), &{:scene, &1})

      true ->
        {:ok, nil}
    end
  end

  def set(_hash), do: :error

  @doc "`Messages::Set::*#to_wire`."
  @spec set_wire(tuple) :: [{String.t(), term}]
  def set_wire({:power, on}), do: [{"power", if(on, do: "on", else: "off")}]
  def set_wire({:brightness, value}), do: [{"brightness", value}]
  def set_wire({:color, rgb}), do: [{"color", rgb_wire(rgb)}]
  def set_wire({:color_temp, kelvin}), do: [{"color_temp_k", kelvin}]
  def set_wire({:zone, name, on}), do: [{"zone", [{"name", name}, {"on", on}]}]
  def set_wire({:scene, name}), do: [{"scene", name}]

  defp zone(%{} = zone) do
    with {:ok, name} <- Types.name(zone["name"] || zone[:name]),
         {:ok, on} <- Types.bool(Map.get(zone, "on", Map.get(zone, :on))),
         do: {:ok, {:zone, name, on}}
  end

  defp zone(_zone), do: :error

  # --- Shared -----------------------------------------------------------------------

  @doc "`Messages::Rgb`: a map with r, g and b (string or atom keys), each 0..255."
  def rgb(%{} = hash) do
    with {:ok, r} <- component(hash, :r),
         {:ok, g} <- component(hash, :g),
         {:ok, b} <- component(hash, :b),
         do: {:ok, %{r: r, g: g, b: b}}
  end

  def rgb(_), do: :error

  defp component(hash, key) do
    case Map.fetch(hash, Atom.to_string(key)) do
      {:ok, value} -> Types.rgb_component(value)
      :error -> if Map.has_key?(hash, key), do: Types.rgb_component(hash[key]), else: :error
    end
  end

  defp zone_states(%{} = zones) do
    Enum.reduce_while(zones, {:ok, %{}}, fn {name, on}, {:ok, acc} ->
      with {:ok, name} <- Types.name(name), {:ok, on} <- Types.bool(on) do
        {:cont, {:ok, Map.put(acc, name, on)}}
      else
        :error -> {:halt, :error}
      end
    end)
  end

  defp zone_states(_), do: :error

  # String keys; atom keys too, for the bridge's own store maps.
  defp present(hash) do
    hash
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp default(hash, key, fallback, fun) do
    case Map.fetch(hash, key) do
      {:ok, value} -> fun.(value)
      :error -> {:ok, fallback}
    end
  end

  defp optional(acc, hash, key, field, fun) do
    case Map.fetch(hash, key) do
      {:ok, value} -> with {:ok, coerced} <- fun.(value), do: {:ok, Map.put(acc, field, coerced)}
      :error -> {:ok, acc}
    end
  end

  defp wrap({:ok, value}, fun), do: {:ok, fun.(value)}
  defp wrap(:error, _fun), do: :error
end
