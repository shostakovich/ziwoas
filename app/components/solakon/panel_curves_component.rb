module Solakon
  # The four panels over the day, each line named next to itself, so the one
  # that falls back in the morning can be told from the one in the evening.
  #
  # Drawn twice: wide for tablets and desktops, narrower and taller for phones,
  # where the wide drawing would shrink to a strip.
  class PanelCurvesComponent < ApplicationComponent
    FRAMES = [
      Chart::Frame.new(key: :wide, width: 720, height: 220, hour_step: 2, named: true,
                       # Room at the right edge for the last hour's label, which
                       # is centred on the tick sitting on the plot's edge.
                       margins: { top: 12, right: 32, bottom: 28, left: 40 }),
      Chart::Frame.new(key: :narrow, width: 360, height: 240, hour_step: 3, named: false,
                       margins: { top: 12, right: 12, bottom: 24, left: 36 })
    ].freeze
    # Grid steps a reader can count in; the first that splits the peak into at
    # most MAX_STEPS parts wins, so the curves fill the plot.
    NICE_STEPS_W = [ 25, 50, 100, 200, 250, 500 ].freeze
    MAX_STEPS = 5

    Entry = Data.define(:key, :label)

    def initialize(panels:)
      @panels = panels
    end

    def empty? = @panels.empty?

    def charts
      FRAMES.map do |frame|
        Chart.new(frame: frame, curves: curves, hours: hours, max_w: max_w, grid_step: grid_step)
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

    def hours
      @hours ||= begin
        all = @panels.hours
        all.empty? ? (0..0) : (all.min..all.max)
      end
    end

    def peak_w = @panels.max.to_f

    def grid_step
      @grid_step ||= NICE_STEPS_W.find { |step| peak_w <= step * MAX_STEPS } ||
                     Plot.round_up(peak_w / MAX_STEPS, to: NICE_STEPS_W.last)
    end

    def max_w = [ Plot.round_up(peak_w, to: grid_step), grid_step ].max
  end
end
