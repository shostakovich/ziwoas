# Per-plug view model for the "Schalten" tab.
class SwitchRow
  LOOKAHEAD = 7.days

  attr_reader :plug, :entries, :state, :last_command, :next_edge, :measurement

  def self.build_all(plugs, now: Time.current)
    plug_ids = plugs.map(&:id)

    rules_by_plug  = SwitchRule.where(plug_id: plug_ids)
                               .order(:at_minute, :id).group_by(&:plug_id)
    states_by_plug = Plugs::State.where(plug_id: plug_ids).index_by(&:plug_id)
    commands_by_plug = SwitchCommand.latest_per_plug(plug_ids)
                                    .order(:created_at, :id).index_by(&:plug_id)
    measurements = Plugs::Measurement.for(plug_ids, now: now)

    plugs.map do |plug|
      rules = rules_by_plug[plug.id] || []
      new(
        plug:         plug,
        entries:      SwitchRules::Schedule.fold(rules),
        state:        states_by_plug[plug.id],
        last_command: commands_by_plug[plug.id],
        next_edge:    SwitchEdgeCalculator.new(rules: rules.select(&:enabled))
                                          .next_edge_per_plug(now, now + LOOKAHEAD).first,
        measurement:  measurements[plug.id],
      )
    end
  end

  def self.build(plug, now: Time.current)
    build_all([ plug ], now: now).first
  end

  def initialize(plug:, entries:, state:, last_command:, next_edge:, measurement:)
    @plug         = plug
    @entries      = entries
    @state        = state
    @last_command = last_command
    @next_edge    = next_edge
    @measurement  = measurement
  end

  def watt         = measurement.watt
  def last_seen_at = measurement.last_seen_at
  def offline?     = measurement.offline?
  def age          = measurement.age

  # The fresher signal wins: a command newer than the last confirmed device
  # state shows optimistically until the Shelly status message catches up.
  def on?
    if last_command && (state.nil? || state.updated_at.nil? || last_command.created_at >= state.updated_at)
      return last_command.action == "on"
    end
    return state.output if state
    false
  end

  def schedule?
    entries.any?(&:enabled?)
  end

  # Schaltzeiten, not rows: a Zeitfenster is one row and two of them.
  def rule_count
    entries.sum { |entry| entry.rules.size }
  end
end
