defmodule Ziwoas.Lights.Light do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "lights" do
    field :color_temp_max_k, :integer
    field :color_temp_min_k, :integer
    field :firmware_scenes, {:array, :string}
    field :key, :string
    field :name, :string
    field :shelly_plug_id, :string
    field :sku, :string
    field :supports_color, :boolean, default: false
    field :supports_color_temp, :boolean, default: false
    field :zones, {:array, :string}
    timestamps()
  end

  @zone_roles %{
    "bottomLightToggle" => :main,
    "rippleLightToggle" => :side,
    "sideLightToggle" => :side,
    "baseLightToggle" => :main,
    "pillarLightToggle" => :side,
    "leftLightToggle" => :side,
    "rightLightToggle" => :side,
    "mainLightToggle" => :main,
    "backgroundLightToggle" => :side
  }

  @default_kelvin {2700, 6500}

  @spec zone_role(String.t()) :: :main | :side | nil
  def zone_role(key), do: Map.get(@zone_roles, key)

  def firmware_scenes(%__MODULE__{firmware_scenes: scenes}), do: scenes || []

  def zones(%__MODULE__{zones: zones}), do: zones || []
  def zone_lamp?(light), do: length(zones(light)) >= 2

  def color_temp_min_k(%__MODULE__{color_temp_min_k: kelvin}),
    do: kelvin || elem(@default_kelvin, 0)

  def color_temp_max_k(%__MODULE__{color_temp_max_k: kelvin}),
    do: kelvin || elem(@default_kelvin, 1)

  @spec settings_changeset(t, map) :: Ecto.Changeset.t()
  def settings_changeset(light, params) do
    light
    |> cast(params, [:name, :shelly_plug_id])
    |> validate_required([:name])
  end
end
