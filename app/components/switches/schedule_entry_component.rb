module Switches
  class ScheduleEntryComponent < ApplicationComponent
    def initialize(entry:, plug:)
      @entry = entry
      @plug  = plug
    end

    private

    attr_reader :entry, :plug

    def window? = entry.is_a?(Switching::Rules::Schedule::Window)

    # +entry.id+ is a Zeitfenster's group and an Einzelschaltung's rule id.
    def row_id = "sw_entry_#{plug.id}_#{entry.id}"

    # An Einzelschaltung's pill is drawn open: its counter-direction is missing.
    def pill_class
      [ "badge rounded-pill fw-normal",
        ("border" unless window?),
        tone_class ].compact.join(" ")
    end

    def tone_class
      return "text-body-secondary text-decoration-line-through" unless entry.enabled?
      window? ? "bg-primary-subtle text-primary-emphasis" : "border-primary text-primary-emphasis"
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
