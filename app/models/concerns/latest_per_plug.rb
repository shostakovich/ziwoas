module LatestPerPlug
  extend ActiveSupport::Concern

  included do
    class_attribute :latest_per_plug_column, instance_accessor: false
  end

  class_methods do
    def latest_per_plug_by(column)
      self.latest_per_plug_column = column
    end

    def latest_per_plug(plug_ids)
      column = latest_per_plug_column
      raise ArgumentError, "#{name} must declare latest_per_plug_by" if column.nil?

      plug_ids = Array(plug_ids)
      return none if plug_ids.empty?

      where(plug_id: plug_ids).where(
        "(plug_id, #{column}) IN (SELECT plug_id, MAX(#{column}) FROM #{table_name} " \
        "WHERE plug_id IN (?) GROUP BY plug_id)", plug_ids
      )
    end
  end
end
