defmodule Ziwoas.Plugs.State do
  @moduledoc "Last known relay output of a plug (`plug_states`), written by `Ziwoas.Plugs.record_output/2`."
  use Ziwoas.Schema

  schema "plug_states" do
    field :output, :boolean
    field :plug_id, :string
    timestamps()
  end
end
