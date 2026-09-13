module Solakon
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
