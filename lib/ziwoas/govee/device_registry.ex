defmodule Ziwoas.Govee.DeviceRegistry do
  @moduledoc false
  require Logger

  alias Ziwoas.Govee.Device
  alias Ziwoas.Lights.Light

  @zone_keys ~w[bottomLightToggle rippleLightToggle sideLightToggle baseLightToggle
                pillarLightToggle leftLightToggle rightLightToggle mainLightToggle
                backgroundLightToggle]
  @virtual_skus ~w[DreamViewScenic]

  defstruct names: %{}, devices: []

  @type t :: %__MODULE__{names: %{String.t() => String.t()}, devices: [Device.t()]}

  def zone_keys, do: @zone_keys

  @spec new(%{String.t() => String.t()}) :: t
  def new(names \\ %{}),
    do: %__MODULE__{names: Map.new(names, fn {mac, name} -> {normalize_mac(mac), name} end)}

  def normalize_mac(mac),
    do: mac |> to_string() |> String.replace(~r/[^0-9A-Za-z]/, "") |> String.upcase()

  def all(%__MODULE__{devices: devices}), do: devices
  def find(%__MODULE__{devices: devices}, key), do: Enum.find(devices, &(&1.key == key))
  def find_by_ip(%__MODULE__{devices: devices}, ip), do: Enum.find(devices, &(&1.ip == ip))

  @spec seed(t, [Light.t()]) :: t
  def seed(%__MODULE__{} = registry, lights),
    do: %{registry | devices: Enum.map(lights, &from_light/1)}

  defp from_light(light) do
    %Device{
      key: light.key,
      api_id: nil,
      sku: light.sku,
      name: light.name,
      supports_color: light.supports_color,
      supports_color_temp: light.supports_color_temp,
      color_temp_min_k: light.color_temp_min_k,
      color_temp_max_k: light.color_temp_max_k,
      zones: Light.zones(light),
      scenes: Light.firmware_scenes(light)
    }
  end

  @spec cloud_list_loaded?(t) :: boolean
  def cloud_list_loaded?(%__MODULE__{devices: devices}),
    do: Enum.any?(devices, &Device.cloud_listed?/1)

  @doc "Listed lamps replace the known ones and keep their IP; unlisted ones stay."
  @spec refresh(t, [map], (map -> {:ok, [map]} | {:error, term})) :: t
  def refresh(%__MODULE__{} = registry, raw_devices, scenes) do
    built =
      for raw <- raw_devices, device = build(registry, raw, scenes), not is_nil(device) do
        case find(registry, device.key) do
          %Device{ip: ip} when not is_nil(ip) -> %{device | ip: ip}
          _ -> device
        end
      end

    listed = last_of_each_key(built)
    by_key = Map.new(listed, &{&1.key, &1})
    known = Enum.map(registry.devices, &Map.get(by_key, &1.key, &1))
    added = Enum.reject(listed, &find(registry, &1.key))
    %{registry | devices: known ++ added}
  end

  # A repeated key keeps its first place and its last value.
  defp last_of_each_key(devices) do
    devices
    |> Enum.map(& &1.key)
    |> Enum.uniq()
    |> Enum.map(fn key -> devices |> Enum.filter(&(&1.key == key)) |> List.last() end)
  end

  @spec record_lan_ip(t, String.t(), String.t()) :: t
  def record_lan_ip(%__MODULE__{} = registry, mac, ip) do
    key = normalize_mac(mac)

    devices =
      Enum.map(registry.devices, fn device ->
        if device.key == key, do: %{device | ip: ip}, else: device
      end)

    %{registry | devices: devices}
  end

  defp build(registry, raw, scenes) do
    api_id = text(raw["device"])

    if api_id == "" or text(raw["sku"]) in @virtual_skus do
      nil
    else
      key = normalize_mac(api_id)
      caps = if is_list(raw["capabilities"]), do: raw["capabilities"], else: []
      instances = Enum.map(caps, & &1["instance"])
      power_only = instances == ["powerSwitch"]

      {scene_names, index} =
        if power_only, do: {[], %{}}, else: load_scenes(registry, key, raw, scenes)

      ct_cap = Enum.find(caps, &(&1["instance"] == "colorTemperatureK"))
      range = get_in(ct_cap || %{}, ["parameters", "range"])

      %Device{
        key: key,
        api_id: api_id,
        sku: text(raw["sku"]),
        name: present(registry.names[key]) || text(raw["deviceName"]),
        ip: nil,
        supports_color: "colorRgb" in instances,
        supports_color_temp: not is_nil(ct_cap),
        color_temp_min_k: range_value(range, "min"),
        color_temp_max_k: range_value(range, "max"),
        zones: Enum.filter(instances, &(&1 in @zone_keys)) |> Enum.uniq(),
        scenes: scene_names,
        scene_index: index,
        power_only: power_only
      }
    end
  end

  defp range_value(range, key) when is_map(range), do: range[key]
  defp range_value(_range, _key), do: nil

  defp load_scenes(registry, key, raw, scenes) do
    case scenes.(raw) do
      {:ok, options} ->
        Enum.reduce(List.wrap(options), {[], %{}}, &add_scene/2)

      {:error, reason} ->
        Logger.warning(
          "Govee.DeviceRegistry: scenes for #{raw["device"]} failed: #{inspect(reason)}"
        )

        # Without ids the known names cannot be played, but the stored scenes are not wiped.
        {known_scenes(registry, key), %{}}
    end
  end

  defp known_scenes(registry, key) do
    case find(registry, key) do
      %Device{scenes: scenes} -> scenes
      nil -> []
    end
  end

  defp add_scene(option, {names, index}) do
    name = text(option["name"])
    value = if is_map(option["value"]), do: option["value"], else: %{}

    if name == "",
      do: {names, index},
      else:
        {names ++ [name], Map.put(index, name, %{id: value["id"], param_id: value["paramId"]})}
  end

  defp present(nil), do: nil
  defp present(name), do: if(String.trim(name) == "", do: nil, else: name)

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp text(_value), do: ""
end
