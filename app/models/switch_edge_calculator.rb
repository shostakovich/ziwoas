# Pure edge computation: no I/O, no clock. One rule, one edge — a rule carries
# its weekdays absolutely, so nothing here knows about midnight.
class SwitchEdgeCalculator
  Edge = Struct.new(:plug_id, :rule_id, :action, :at, keyword_init: true)

  # :off sorts before :on, so "last edge wins" resolves a tie towards on.
  ACTION_ORDER = { off: 0, on: 1 }.freeze

  def initialize(rules:, timezone: Time.zone)
    @rules = rules
    @tz    = timezone
  end

  # All edges with from < at <= to, ascending by time.
  def edges_between(from, to)
    return [] if to <= from

    first_date = from.in_time_zone(@tz).to_date
    last_date  = to.in_time_zone(@tz).to_date
    (first_date..last_date)
      .flat_map { |date| edges_for_date(date) }
      .select { |e| e.at > from && e.at <= to }
      .sort_by { |e| [ e.at, ACTION_ORDER[e.action] ] }
  end

  # At most one edge per plug: the latest within the interval.
  def latest_edge_per_plug(from, to)
    edges_between(from, to).group_by(&:plug_id).map { |_, edges| edges.last }
  end

  # At most one edge per plug: the earliest within the interval. Mirror of
  # latest_edge_per_plug, so the status line announces what the tick performs.
  def next_edge_per_plug(from, to)
    edges_between(from, to).group_by(&:plug_id).map { |_, edges| tie_winner(edges) }
  end

  private

  # Among the edges sharing the earliest timestamp, the one ACTION_ORDER ranks
  # highest — the same winner "last edge wins" picks.
  def tie_winner(edges)
    edges.take_while { |e| e.at == edges.first.at }.last
  end

  def edges_for_date(date)
    @rules.select { |r| r.days.include?(date.cwday) }.map do |r|
      Edge.new(plug_id: r.plug_id, rule_id: r.id, action: r.action.to_sym,
               at: local_time(date, r.at_minute))
    end
  end

  def local_time(date, minutes)
    @tz.local(date.year, date.month, date.day, minutes / 60, minutes % 60)
  end
end
