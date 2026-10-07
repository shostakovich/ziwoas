defmodule Ziwoas.Plugs.DailyTotal do
  @moduledoc "Energy of one plug on one local day (`daily_totals`)."
  use Ziwoas.Schema

  @primary_key false
  schema "daily_totals" do
    # ISO date as text ("YYYY-MM-DD").
    field :date, :string, primary_key: true
    field :energy_wh, :float
    field :plug_id, :string, primary_key: true
  end
end
