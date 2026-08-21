class FlattenSwitchWindowsIntoSwitchRules < ActiveRecord::Migration[8.1]
  # Throwaway readers, so the migration never depends on the app's models —
  # SwitchWindow is deleted in this very commit.
  class Window < ActiveRecord::Base
    self.table_name = "switch_windows"
  end

  class Rule < ActiveRecord::Base
    self.table_name = "switch_rules"
  end

  def up
    create_table :switch_rules do |t|
      t.string  :plug_id,   null: false
      t.string  :action,    null: false               # "on" | "off"
      t.integer :at_minute, null: false               # Minuten seit Mitternacht, 0..1439
      t.json    :days,      null: false               # ISO-Wochentage 1..7, absolut
      t.boolean :enabled,   null: false, default: true
      t.string  :group_id                             # UUID, nullable
      t.timestamps
    end
    add_index :switch_rules, :plug_id
    add_index :switch_rules, [ :group_id, :action ], unique: true, where: "group_id IS NOT NULL"

    rows = Window.order(:id).flat_map { |w| Switching::Rules::WindowConversion.split(w.attributes) }
    Rule.insert_all(rows) if rows.any?

    drop_table :switch_windows

    # The watermark moves from one global row to one per plug. The old row says
    # nothing about any single plug, so it is discarded rather than fanned out —
    # the tick's Karenz covers the resulting lookback.
    rebuild_scheduler_states(per_plug: true)
  end

  def down
    create_table :switch_windows do |t|
      t.string  :plug_id, null: false
      t.integer :on_at,   null: false
      t.integer :off_at,  null: false
      t.json    :days,    null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :switch_windows, :plug_id

    rules = Rule.order(:id).map(&:attributes)
    rows  = Switching::Rules::WindowConversion.join(rules)
    Window.insert_all(rows) if rows.any?

    dropped = rules.size - rows.size * 2
    say "#{dropped} Einzelschaltung(en) verworfen — das Zeitfenster kennt keine ungepaarte Schaltzeit." if dropped.positive?

    drop_table :switch_rules

    rebuild_scheduler_states(per_plug: false)
  end

  private

  # SQLite cannot add a NOT NULL column without a default, and the watermarks
  # are worthless across the change either way, so the table is simply rebuilt.
  def rebuild_scheduler_states(per_plug:)
    drop_table :scheduler_states
    create_table :scheduler_states do |t|
      t.string   :plug_id, null: false if per_plug
      t.datetime :last_tick_at, null: false
      t.timestamps
    end
    add_index :scheduler_states, :plug_id, unique: true if per_plug
  end
end
