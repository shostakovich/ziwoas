defmodule Ziwoas.Plugs.DailyTotal do
  @moduledoc false
  use Ziwoas.Schema

  @primary_key false
  schema "daily_totals" do
    field :date, :date, primary_key: true
    field :energy_wh, :float
    field :plug_id, :string, primary_key: true
  end
end
