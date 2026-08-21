module Plugs
  class Sample < ApplicationRecord
    self.table_name = "samples"
    include LatestPerPlug
    latest_per_plug_by :ts

    self.primary_key = [ :plug_id, :ts ]

    validates :plug_id, presence: true
    validates :ts, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :apower_w, presence: true, numericality: true
    validates :aenergy_wh, presence: true, numericality: true
  end
end
