module Switches
  # One row of a plug's schedule. Whether the row is a Zeitfenster or an
  # Einzelschaltung decides three things at once — which resource the buttons
  # address, which word the aria labels use, and how the pill looks. Those
  # answers belong together, hence a component rather than two near-identical
  # partials.
  class ScheduleEntryComponent < ApplicationComponent
    def initialize(entry:, plug:)
      @entry = entry
      @plug  = plug
    end

    private

    attr_reader :entry, :plug

    def window? = entry.is_a?(Switching::Rules::Schedule::Window)

    # +entry.id+ is the group of a Zeitfenster and the rule id of an
    # Einzelschaltung, so one expression serves both.
    def row_id = "sw_entry_#{plug.id}_#{entry.id}"

    def pill_class
      [ "sw-pill", ("single" unless window?), ("paused" unless entry.enabled?) ].compact.join(" ")
    end

    def noun = window? ? "Zeitfenster" : "Schaltzeit"

    def direction = entry.action == "on" ? "→ an" : "→ aus"

    def entry_path
      window? ? switch_window_path(plug_id: plug.id, group_id: entry.id)
              : switch_rule_path(plug_id: plug.id, id: entry.id)
    end

    def edit_path
      window? ? edit_switch_window_path(plug_id: plug.id, group_id: entry.id)
              : edit_switch_rule_path(plug_id: plug.id, id: entry.id)
    end

    def enabled_path
      window? ? enabled_switch_window_path(plug_id: plug.id, group_id: entry.id)
              : enabled_switch_rule_path(plug_id: plug.id, id: entry.id)
    end
  end
end
