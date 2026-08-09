module SwitchRules
  # The way back from flat switch rules to the rows a plug card shows: a
  # Zeitfenster (two rules of one group) or an Einzelschaltung (one rule on its
  # own). Pure Ruby — rules only need to answer id, action, at_minute, days,
  # enabled and group_id, so this needs neither database nor rendering to test.
  class Schedule
    # The weekdays a human sees are the on rule's: the off rule of a window past
    # midnight carries them shifted one day forward, and not reading them undoes
    # the shift.
    Window = Data.define(:on, :off) do
      def id        = on.group_id
      def days      = on.days
      def at_minute = on.at_minute
      def enabled?  = on.enabled
      def rules     = [ on, off ]
    end

    Single = Data.define(:rule) do
      def id        = rule.id
      def action    = rule.action
      def days      = rule.days
      def at_minute = rule.at_minute
      def enabled?  = rule.enabled
      def rules     = [ rule ]
    end

    class << self
      # Earliest first; a tie is settled by the smallest rule id, so the order
      # never wobbles.
      def fold(rules)
        rules
          .group_by(&:group_id)
          .flat_map { |group_id, group| group_id.nil? ? singles(group) : entries_for_group(group) }
          .sort_by { |entry| [ entry.at_minute, entry.rules.map(&:id).min ] }
      end

      private

      # A group that is not a pair becomes singles: visible and deletable rather
      # than a blank row. Unreachable by construction, so no repair and no log —
      # folding only has to survive it.
      def entries_for_group(group)
        on  = group.find { |r| r.action == "on" }
        off = group.find { |r| r.action == "off" }
        on && off ? [ Window.new(on: on, off: off) ] : singles(group)
      end

      def singles(rules) = rules.map { |rule| Single.new(rule: rule) }
    end
  end
end
