module Switches
  # One row of a plug's schedule. What the row *is* — a Zeitfenster (the two
  # rules of one group) or an Einzelschaltung (a single rule) — decides three
  # things at once: which resource the three buttons address, which word the
  # aria labels use, and whether the pill is dashed and carries a direction.
  # Those three answers belong together, which is why this is a component and
  # not two nearly identical partials.
  class ScheduleEntryComponent < ApplicationComponent
    def initialize(entry:, plug:)
      @entry = entry
      @plug  = plug
    end

    private

    attr_reader :entry, :plug

    def window? = entry.is_a?(SwitchRules::Schedule::Window)

    # A Zeitfenster is addressed by its group, an Einzelschaltung by its rule
    # id; +entry.id+ already hands out the right one, so the row id is the same
    # expression for both.
    def row_id = "sw_entry_#{plug.id}_#{entry.id}"

    def pill_class
      [ "sw-pill", ("single" unless window?), ("paused" unless entry.enabled?) ].compact.join(" ")
    end

    # The word the glossary uses for the thing the button acts on — the pair is
    # a Zeitfenster, the lone rule is a Schaltzeit.
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
