module SwitchRules
  # The way back from flat switch rules to the rows a plug card shows: a
  # Zeitfenster (two rules of one group) or an Einzelschaltung (one rule on its
  # own). Pure Ruby — rules only need to respond to id, action, at_minute, days,
  # enabled and group_id, so this is testable without a database and without
  # rendering.
  #
  # Called from SwitchRow.build_all, where the bundled loading already lives,
  # not from the view.
  class Schedule
    # Two rules of one group, shown and edited as one row. The weekdays a human
    # sees are the on rule's: when the off time falls before the on time, the
    # window runs past midnight and the off rule carries its weekdays shifted
    # one day forward (Mo-Fr an, Di-Sa aus). Undoing that shift is a matter of
    # not reading the off rule's days — the same move SwitchRules::WindowConversion
    # makes when it joins rules back into a window.
    Window = Data.define(:on, :off) do
      def id        = on.group_id
      def days      = on.days
      def at_minute = on.at_minute
      def enabled?  = on.enabled
      def rules     = [ on, off ]
    end

    # One rule without a partner: the Einzelschaltung, named by its direction.
    Single = Data.define(:rule) do
      def id        = rule.id
      def action    = rule.action
      def days      = rule.days
      def at_minute = rule.at_minute
      def enabled?  = rule.enabled
      def rules     = [ rule ]
    end

    class << self
      # The rules of one plug -> its entries, earliest first. A tie is settled
      # by the smallest rule id in the entry, so the order never wobbles.
      def fold(rules)
        rules
          .group_by(&:group_id)
          .flat_map { |group_id, group| group_id.nil? ? singles(group) : entries_for_group(group) }
          .sort_by { |entry| [ entry.at_minute, entry.rules.map(&:id).min ] }
      end

      private

      # A group that is not a pair — one half missing, or both halves pointing
      # the same way — cannot be shown as a window. It becomes singles: visible
      # and deletable rather than a blank row. The case is unreachable by
      # construction and gets no repair, no label and no log; folding only has
      # to survive it.
      def entries_for_group(group)
        on  = group.find { |r| r.action == "on" }
        off = group.find { |r| r.action == "off" }
        on && off ? [ Window.new(on: on, off: off) ] : singles(group)
      end

      def singles(rules) = rules.map { |rule| Single.new(rule: rule) }
    end
  end
end
