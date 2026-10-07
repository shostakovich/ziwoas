defmodule Ziwoas.Govee.Messages do
  @moduledoc """
  The typed MQTT wire contracts between the Govee bridge and the subscriber.
  Parsing a raw (JSON-decoded) map returns `{:ok, map}` or `:error` for a
  message that does not coerce; `*_wire/1` give the wire object as a map for
  `JSON.encode!/1`.

  A parsed state is a map holding only the keys the message had: `:on` and
  `:reachable` always, `:brightness`, `:color` (`%{r:, g:, b:}`),
  `:color_temp_k`, `:zone_states` (string keys) when given.
  """
  import Bitwise

  alias Ziwoas.Govee.Types

  # --- State (govees/<key>/state) ---------------------------------------------

  @doc "A state message; nil values are dropped, so defaults apply."
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

  @doc "A parsed state as its wire object."
  @spec state_wire(map) :: map
  def state_wire(state) do
    for key <- [:brightness, :color, :color_temp_k, :zone_states],
        Map.has_key?(state, key),
        into: %{"on" => state.on, "reachable" => state.reachable},
        do: {Atom.to_string(key), wire_value(key, state[key])}
  end

  defp wire_value(:color, color), do: rgb_wire(color)
  defp wire_value(_key, value), do: value

  defp rgb_wire(%{r: r, g: g, b: b}), do: %{"r" => r, "g" => g, "b" => b}

  # --- Config (govees/<key>/config) -------------------------------------------

  @doc "A config message: what the bridge knows of a lamp."
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

  @doc "The wire object of a parsed config or a `Ziwoas.Govee.Device`."
  @spec config_wire(map) :: map
  def config_wire(config) do
    %{
      "sku" => config.sku,
      "name" => config.name,
      "supports_color" => config.supports_color,
      "supports_color_temp" => config.supports_color_temp,
      "color_temp_min_k" => config.color_temp_min_k,
      "color_temp_max_k" => config.color_temp_max_k,
      "zones" => config.zones,
      "scenes" => config.scenes
    }
  end

  # --- DeviceState (Platform API capabilities) -----------------------------------

  @doc """
  The Platform API's capability states as store telemetry: an unreachable lamp
  is never on, whatever the cloud remembers. Numbers may come as strings.
  """
  @spec device_telemetry(map, [String.t()]) :: {:ok, map} | :error
  def device_telemetry(map, zone_keys) do
    online = Map.get(map, "online", true)
    reachable = online === true or online == 1

    telemetry = %{
      on: reachable and to_int(map["powerSwitch"]) == 1,
      reachable: reachable
    }

    rgb = to_int(map["colorRgb"])

    with {:ok, telemetry} <-
           optional(telemetry, map, "brightness", :brightness, &Types.brightness/1),
         {:ok, telemetry} <- color_or_kelvin(telemetry, map, rgb) do
      zones =
        for zone <- zone_keys,
            (value = map[zone]) not in [nil, ""],
            into: %{},
            do: {zone, to_int(value) == 1}

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
    if to_int(map["colorTemperatureK"]) > 0,
      do: optional(telemetry, map, "colorTemperatureK", :color_temp_k, &Types.kelvin/1),
      else: {:ok, telemetry}
  end

  # --- Set verbs (govees/<key>/set) -----------------------------------------------

  @doc """
  A set message: one verb, or `{:ok, nil}` for an unknown one. Verbs:
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

  @doc "A verb as its wire object."
  @spec set_wire(tuple) :: map
  def set_wire({:power, on}), do: %{"power" => if(on, do: "on", else: "off")}
  def set_wire({:brightness, value}), do: %{"brightness" => value}
  def set_wire({:color, rgb}), do: %{"color" => rgb_wire(rgb)}
  def set_wire({:color_temp, kelvin}), do: %{"color_temp_k" => kelvin}
  def set_wire({:zone, name, on}), do: %{"zone" => %{"name" => name, "on" => on}}
  def set_wire({:scene, name}), do: %{"scene" => name}

  defp zone(%{} = zone) do
    with {:ok, name} <- Types.name(zone["name"] || zone[:name]),
         {:ok, on} <- Types.bool(Map.get(zone, "on", Map.get(zone, :on))),
         do: {:ok, {:zone, name, on}}
  end

  defp zone(_zone), do: :error

  # --- Shared -----------------------------------------------------------------------

  @doc "A colour: a map with r, g and b (string or atom keys), each 0..255."
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

  # Lenient: the cloud sends numbers or numeric strings; anything else counts as 0.
  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  defp to_int(_value), do: 0

  defp wrap({:ok, value}, fun), do: {:ok, fun.(value)}
  defp wrap(:error, _fun), do: :error
end
