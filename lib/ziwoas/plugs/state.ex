defmodule Ziwoas.Plugs.State do
  @moduledoc false
  use Ziwoas.Schema

  schema "plug_states" do
    field :output, :boolean
    field :plug_id, :string
    timestamps()
  end
end
