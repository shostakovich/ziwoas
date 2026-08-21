module LatestPerPlug
  extend ActiveSupport::Concern

  class_methods do
    def latest_per_plug_by(column)
      @latest_per_plug_column = column
    end

    def latest_per_plug(plug_ids)
      plug_ids = Array(plug_ids)
      return none if plug_ids.empty?

      column = @latest_per_plug_column
      where(plug_id: plug_ids).where(
        "(plug_id, #{column}) IN (SELECT plug_id, MAX(#{column}) FROM #{table_name} " \
        "WHERE plug_id IN (?) GROUP BY plug_id)", plug_ids
      )
    end
  end
end
