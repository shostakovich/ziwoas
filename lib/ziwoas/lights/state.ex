defmodule Ziwoas.Lights.State do
  @moduledoc false
  use Ziwoas.Schema

  schema "light_states" do
    field :brightness, :integer
    field :color_b, :integer
    field :color_g, :integer
    field :color_r, :integer
    field :color_temp_k, :integer
    field :last_seen_at, :utc_datetime_usec
    field :light_key, :string
    field :on, :boolean
    field :reachable, :boolean
    field :zone_states, :map
    timestamps()
  end
end
