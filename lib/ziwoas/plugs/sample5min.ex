defmodule Ziwoas.Plugs.Sample5min do
  @moduledoc false
  use Ziwoas.Schema

  @primary_key false
  schema "samples_5min" do
    field :avg_power_w, :float
    field :bucket_ts, :integer, primary_key: true
    field :energy_delta_wh, :float
    field :plug_id, :string, primary_key: true
    field :sample_count, :integer
  end
end
