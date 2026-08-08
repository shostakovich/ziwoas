module SwitchRules
  # Pure translation between the old paired switch_windows row and the two flat
  # switch_rules rows it becomes. No Active Record, no I/O, no clock — the
  # migration body is a naked call to this, so that the interesting cases stay
  # testable (SimpleCov does not look inside db/).
  #
  # Rows are plain string-keyed hashes on both sides, exactly the shape
  # +attributes+ hands out and +insert_all+ takes back.
  module WindowConversion
    DAYS_PER_WEEK = 7

    class << self
      # One window hash -> the on and the off rule it becomes, joined by a
      # fresh group. An off time before the on time means the window runs past
      # midnight: the off rule then carries its weekdays shifted one day
      # forward, so "Mo-Fr 22:00 an / 06:00 aus" is stored as an on rule on
      # Mo-Fr and an off rule on Di-Sa. The day shift leaves the edge
      # calculation and becomes plain stored data.
      def split(window)
        group_id = SecureRandom.uuid
        days     = Array(window["days"])
        crosses  = window["on_at"] > window["off_at"]

        [
          rule(window, "on",  window["on_at"],  days, group_id),
          rule(window, "off", window["off_at"], crosses ? next_day(days) : days, group_id)
        ]
      end

      # The mirror of +split+: rule hashes -> window hashes, one per complete
      # group. Anything that cannot become a window — a rule without a group, a
      # group missing its partner, a group pointing twice the same way — is
      # dropped, because the old table has no shape for it.
      def join(rules)
        rules
          .reject { |r| r["group_id"].nil? }
          .group_by { |r| r["group_id"] }
          .filter_map { |_, group| window(group) }
      end

      private

      def next_day(days)
        days.map { |d| d % DAYS_PER_WEEK + 1 }.sort
      end

      def rule(window, action, at_minute, days, group_id)
        {
          "plug_id"    => window["plug_id"],
          "action"     => action,
          "at_minute"  => at_minute,
          "days"       => days,
          "enabled"    => window["enabled"],
          "group_id"   => group_id,
          "created_at" => window["created_at"],
          "updated_at" => window["updated_at"]
        }
      end

      def window(group)
        on  = group.find { |r| r["action"] == "on" }
        off = group.find { |r| r["action"] == "off" }
        return nil if on.nil? || off.nil?

        {
          "plug_id"    => on["plug_id"],
          "on_at"      => on["at_minute"],
          "off_at"     => off["at_minute"],
          # The on rule already carries the window's own weekdays; the off
          # rule's shifted days are redundant with them, so undoing the shift
          # is simply a matter of not looking at them.
          "days"       => on["days"],
          "enabled"    => on["enabled"],
          "created_at" => on["created_at"],
          "updated_at" => on["updated_at"]
        }
      end
    end
  end
end
