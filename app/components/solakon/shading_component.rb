module Solakon
  # The section that answers where the garden stands in the way: the map of the
  # sky, the day's shape per month, and the four panels beside each other. It
  # holds the order and the one empty state the three share.
  class ShadingComponent < ApplicationComponent
    def initialize(report:)
      @report = report
    end

    def empty? = @report.empty?

    def map = @report.map

    def profiles = @report.profiles

    def panels = @report.panels
  end
end
