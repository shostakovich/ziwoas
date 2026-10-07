defmodule Ziwoas.Plugs.Sample do
  @moduledoc "One measurement of a plug (`samples`). `ts` is Unix seconds, not a datetime."
  use Ziwoas.Schema

  @primary_key false
  schema "samples" do
    field :aenergy_wh, :float
    field :apower_w, :float
    field :plug_id, :string, primary_key: true
    field :ts, :integer, primary_key: true
  end
end
