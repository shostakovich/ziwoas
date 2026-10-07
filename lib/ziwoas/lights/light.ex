defmodule Ziwoas.Lights.Light do
  @moduledoc "A Govee light (`lights`). `zones` and `firmware_scenes` are JSON arrays in text columns."
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

  # Toggle instance key → display label and role; only listed instances are zones.
  @zone_meta %{
    "bottomLightToggle" => {"Leselicht", "main"},
    "rippleLightToggle" => {"Welle", "side"},
    "sideLightToggle" => {"Seite", "side"},
    "baseLightToggle" => {"Sockel", "main"},
    "pillarLightToggle" => {"Säule", "side"},
    "leftLightToggle" => {"Links", "side"},
    "rightLightToggle" => {"Rechts", "side"},
    "mainLightToggle" => {"Hauptlampe", "main"},
    "backgroundLightToggle" => {"Ring", "side"}
  }

  @default_kelvin {2700, 6500}
  @plush_types %{
    "H60B0" => "uplighter",
    "H607C" => "floorlamp",
    "H6038" => "sconce",
    "H60A6" => "ceiling"
  }

  @doc "`{label, role}` of a zone key, nil for a control toggle."
  def zone_meta(key), do: Map.get(@zone_meta, key)

  def plush_type(%__MODULE__{sku: sku}),
    do: Map.get(@plush_types, String.upcase(sku || ""), "generic")

  def plush_image(light, on), do: "lamp_#{plush_type(light)}_#{if on, do: "on", else: "off"}.webp"

  @doc "Always a list, even before discovery has written one."
  def firmware_scenes(%__MODULE__{firmware_scenes: scenes}), do: scenes || []

  def zones(%__MODULE__{zones: zones}), do: zones || []
  def zone_lamp?(light), do: length(zones(light)) >= 2

  @doc "The white range the Govee capabilities reported, else 2700–6500 K."
  def color_temp_min_k(%__MODULE__{color_temp_min_k: kelvin}),
    do: kelvin || elem(@default_kelvin, 0)

  def color_temp_max_k(%__MODULE__{color_temp_max_k: kelvin}),
    do: kelvin || elem(@default_kelvin, 1)

  @doc """
  The settings form (`LightsController#update`): name and Shelly plug, nothing
  the bridge manages. A blank plug choice stays `""`, as Rails stores it.
  """
  @spec settings_changeset(t, map) :: Ecto.Changeset.t()
  def settings_changeset(light, params) do
    changeset = cast(light, params, [:name, :shelly_plug_id], empty_values: [])

    if Ziwoas.Form.blank?(get_field(changeset, :name)),
      do: add_error(changeset, :name, "can't be blank"),
      else: changeset
  end

  @doc "Rails' `errors.full_messages` with their attribute: the humanised name, then the message."
  @spec full_messages(Ecto.Changeset.t()) :: [{atom, String.t()}]
  def full_messages(changeset) do
    for {field, {message, _}} <- Enum.reverse(changeset.errors),
        do: {field, "#{field |> Atom.to_string() |> String.capitalize()} #{message}"}
  end
end
