module Solakon
  # Drawn twice: on a phone the wide drawing would shrink to a strip.
  class PanelCurvesComponent < ApplicationComponent
    include ChartParts

    FRAMES = [
      Chart::Frame.new(key: :wide, width: 720, height: 220, hour_step: 2, named: true,
                       margins: { top: 12, right: 88, bottom: 28, left: 40 }),
      Chart::Frame.new(key: :narrow, width: 360, height: 240, hour_step: 3, named: false,
                       margins: { top: 12, right: 12, bottom: 24, left: 36 })
    ].freeze
    NICE_STEPS_W = [ 25, 50, 100, 200, 250, 500 ].freeze
    MAX_STEPS = 5

    Entry = Data.define(:key, :label)

    def initialize(panels:)
      @panels = panels
    end

    def empty? = @panels.empty?

    def charts
      FRAMES.map do |frame|
        Chart.new(frame: frame, curves: curves, hours: hours, scale: scale)
      end
    end

    def legend = curves.map { |curve| Entry.new(key: curve.key, label: Chart.name_of(curve.key)) }

    def period
      return nil if @panels.since.nil?

      "seit #{@panels.since.strftime('%d.%m.%Y')} · #{@panels.days} #{@panels.days == 1 ? 'Tag' : 'Tage'}"
    end

    def note
      "Gezählt sind nur Tage, an denen alle vier Panels geliefert haben — ein Panel, das noch nicht " \
        "angeschlossen war, meldet null Watt und würde seine eigene Linie nach unten ziehen."
    end

    private

    def curves = @panels.curves

    def hours = @hours ||= Plot.extent(@panels.hours)

    def scale = @scale ||= Plot.nice_scale(@panels.max, steps: NICE_STEPS_W, max_steps: MAX_STEPS)
  end
end
