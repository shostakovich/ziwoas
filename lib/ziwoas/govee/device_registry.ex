defmodule Ziwoas.Govee.DeviceRegistry do
  @moduledoc """
  Rails' `Govees::DeviceRegistry`: the canonical lamp list, built from the Platform
  API (id, sku, name, capabilities, scenes) and curated — segment capabilities
  dropped, zones limited to `zone_keys/0`, scenes reduced to names plus an internal
  name → `%{id, param_id}` index, Govee's virtual DreamView scene "devices" left
  out. LAN discovery only contributes the IP. Pure: `build/3` takes the API's raw
  device list and a scene loader.
  """
  require Logger

  alias Ziwoas.Govee.Device

  # Light::ZONE_META's keys, in its order.
  @zone_keys ~w[bottomLightToggle rippleLightToggle sideLightToggle baseLightToggle
                pillarLightToggle leftLightToggle rightLightToggle mainLightToggle
                backgroundLightToggle]
  @virtual_skus ~w[DreamViewScenic]

  defstruct names: %{}, devices: []

  @type t :: %__MODULE__{names: %{String.t() => String.t()}, devices: [Device.t()]}

  def zone_keys, do: @zone_keys

  @doc "A registry; `names` maps a MAC (any separators) to a configured name."
  @spec new(%{String.t() => String.t()}) :: t
  def new(names \\ %{}),
    do: %__MODULE__{names: Map.new(names, fn {mac, name} -> {normalize_mac(mac), name} end)}

  @doc "The key of a MAC: alphanumerics only, upper case."
  def normalize_mac(mac),
    do: mac |> to_string() |> String.replace(~r/[^0-9A-Za-z]/, "") |> String.upcase()

  def all(%__MODULE__{devices: devices}), do: devices
  def find(%__MODULE__{devices: devices}, key), do: Enum.find(devices, &(&1.key == key))
  def find_by_ip(%__MODULE__{devices: devices}, ip), do: Enum.find(devices, &(&1.ip == ip))

  @doc """
  `refresh!` with the API's device list: rebuilds every device, keeping a LAN IP
  found earlier. `scenes` is `fn raw -> {:ok, options} | {:error, message} end`.
  """
  @spec refresh(t, [map], (map -> {:ok, [map]} | {:error, String.t()})) :: t
  def refresh(%__MODULE__{} = registry, raw_devices, scenes) do
    built =
      for raw <- raw_devices, device = build(registry, raw, scenes), not is_nil(device) do
        case find(registry, device.key) do
          %Device{ip: ip} when not is_nil(ip) -> %{device | ip: ip}
          _ -> device
        end
      end

    # Rails builds a Hash by key: a repeated key keeps its first place, the last value.
    devices =
      built
      |> Enum.map(& &1.key)
      |> Enum.uniq()
      |> Enum.map(fn key -> built |> Enum.filter(&(&1.key == key)) |> List.last() end)

    %{registry | devices: devices}
  end

  @doc "`record_lan_ip`: the IP of the device with this MAC (separators ignored)."
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
    api_id = ruby_to_s(raw["device"])

    if api_id == "" or ruby_to_s(raw["sku"]) in @virtual_skus do
      nil
    else
      key = normalize_mac(api_id)
      caps = if is_list(raw["capabilities"]), do: raw["capabilities"], else: []
      instances = Enum.map(caps, & &1["instance"])
      power_only = instances == ["powerSwitch"]
      {scene_names, index} = if power_only, do: {[], %{}}, else: load_scenes(raw, scenes)
      ct_cap = Enum.find(caps, &(&1["instance"] == "colorTemperatureK"))
      range = get_in(ct_cap || %{}, ["parameters", "range"])

      %Device{
        key: key,
        api_id: api_id,
        sku: ruby_to_s(raw["sku"]),
        name: present(registry.names[key]) || ruby_to_s(raw["deviceName"]),
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

  defp load_scenes(raw, scenes) do
    case scenes.(raw) do
      {:ok, options} ->
        Enum.reduce(List.wrap(options), {[], %{}}, fn option, {names, index} ->
          name = ruby_to_s(option["name"])
          value = if is_map(option["value"]), do: option["value"], else: %{}

          if name == "",
            do: {names, index},
            else:
              {names ++ [name],
               Map.put(index, name, %{id: value["id"], param_id: value["paramId"]})}
        end)

      {:error, message} ->
        Logger.warning("Govee.DeviceRegistry: scenes for #{raw["device"]} failed: #{message}")
        {[], %{}}
    end
  end

  defp present(nil), do: nil
  defp present(name), do: if(String.trim(name) == "", do: nil, else: name)

  defp ruby_to_s(nil), do: ""
  defp ruby_to_s(value) when is_binary(value), do: value
  defp ruby_to_s(value) when is_integer(value), do: Integer.to_string(value)
  defp ruby_to_s(value), do: to_string(value)
end
