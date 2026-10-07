defmodule Ziwoas.Govee.Device do
  @moduledoc "Rails' `Govees::Device`: one lamp as the bridge knows it. `ip` comes from LAN discovery."
  @enforce_keys [:key, :api_id, :sku, :name]
  defstruct [
    :key,
    :api_id,
    :sku,
    :name,
    :ip,
    :color_temp_min_k,
    :color_temp_max_k,
    supports_color: false,
    supports_color_temp: false,
    zones: [],
    scenes: [],
    scene_index: %{},
    power_only: false
  ]

  @type t :: %__MODULE__{}
end
