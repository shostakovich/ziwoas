defmodule Ziwoas.Plugs.Sample do
  @moduledoc false
  use Ziwoas.Schema

  @primary_key false
  schema "samples" do
    field :aenergy_wh, :float
    field :apower_w, :float
    field :plug_id, :string, primary_key: true
    field :ts, :integer, primary_key: true
  end
end
