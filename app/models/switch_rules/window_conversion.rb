module SwitchRules
  # Pure translation between the old paired switch_windows row and the two flat
  # switch_rules rows it becomes: string-keyed hashes in, string-keyed hashes
  # out. The migration body is a naked call to this, because SimpleCov does not
  # look inside db/ and logic there would go unmeasured.
  module WindowConversion
    DAYS_PER_WEEK = 7

    class << self
      # An off time before the on time means the window runs past midnight, so
      # the off rule carries its weekdays shifted one day forward: "Mo–Fr 22:00
      # an / 06:00 aus" becomes on Mo–Fr, off Di–Sa. The shift leaves the edge
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

      # The mirror of +split+. Anything that cannot become a window — no group,
      # a missing partner, twice the same direction — is dropped: the old table
      # has no shape for it.
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
          # Undoing the day shift is a matter of not reading the off rule's days.
          "days"       => on["days"],
          "enabled"    => on["enabled"],
          "created_at" => on["created_at"],
          "updated_at" => on["updated_at"]
        }
      end
    end
  end
end
