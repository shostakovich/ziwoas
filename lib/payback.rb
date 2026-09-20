require "date"

# How far the savings have carried the plant towards its acquisition cost, and
# when they will have covered it. Every figure rests on the days actually on
# record: savings before the data start are never estimated, so the payback is
# reckoned late rather than early.
class Payback
  # Below this many days on record a projection says more about the season than
  # about the plant, so none is made.
  MIN_PROJECTION_DAYS = 90
  # A full year levels out the seasons; a shorter record uses everything it has.
  PROJECTION_WINDOW_DAYS = 365

  def initialize(acquisition_cost_eur:, daily_savings:, today: Date.current)
    @cost  = acquisition_cost_eur
    @days  = daily_savings.sort_by(&:first)
    @today = today
  end

  def costed? = @cost.positive?

  def saved_eur = @days.sum { |_date, eur| eur }

  def data_start = @days.first&.first

  def covered_ratio
    return nil unless costed?

    [ saved_eur / @cost, 1.0 ].min
  end

  def reached? = costed? && saved_eur >= @cost

  # The day the running total first reached the cost.
  def reached_on
    return nil unless reached?

    running = 0.0
    @days.each do |date, eur|
      running += eur
      return date if running >= @cost
    end
    nil
  end

  def projection_days = projection_window.length

  def projected_date
    return nil if !costed? || reached?
    return nil if projection_days < MIN_PROJECTION_DAYS

    rate = average_daily_eur
    return nil unless rate.positive?

    @today + ((@cost - saved_eur) / rate).ceil
  end

  private

  def projection_window
    cutoff = @today - (PROJECTION_WINDOW_DAYS - 1)
    @days.select { |date, _eur| date >= cutoff }
  end

  def average_daily_eur
    window = projection_window
    window.sum { |_date, eur| eur } / window.length
  end
end
