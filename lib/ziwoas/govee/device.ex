defmodule Ziwoas.Govee.Device do
  @moduledoc false
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

  @typedoc "A lamp seeded from the database has no `api_id` until the cloud lists it."
  @type t :: %__MODULE__{api_id: String.t() | nil}

  @spec cloud_listed?(t) :: boolean
  def cloud_listed?(%__MODULE__{api_id: api_id}), do: not is_nil(api_id)
end
