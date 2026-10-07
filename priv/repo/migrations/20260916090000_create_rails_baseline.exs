defmodule Ziwoas.Repo.Migrations.CreateRailsBaseline do
  @moduledoc """
  The schema Rails left behind (`db/schema.rb` at version 20260916090000), with the
  column order of the production database. Every table and index is created only if
  missing: on the database Rails hands over (`Ziwoas.Release.adopt_rails_database!/0`)
  this changes nothing, on an empty file it builds the same schema.
  """
  use Ecto.Migration

  # Declared types decide a column's affinity in SQLite. Where Ecto's own type would
  # change the one Rails' column has, the Rails type is spelled out (ecto_sqlite3 passes
  # any other atom through upcased): :boolean would be INTEGER, :utc_datetime and :map
  # TEXT, while Rails' boolean, datetime(6) and json are NUMERIC. :real stands for
  # Rails' float (REAL); Ecto's :float would be NUMERIC.
  @boolean :BOOLEAN
  @datetime :"DATETIME(6)"
  @json :JSON
  @timestamps [inserted_at: :created_at, type: @datetime]

  def up do
    create_if_not_exists table(:cost_items) do
      add :label, :string, null: false
      add :amount_eur, :decimal, precision: 10, scale: 2, null: false
      add :spent_on, :string, null: false
      add :note, :string
      timestamps(@timestamps)
    end

    create_if_not_exists index(:cost_items, [:spent_on], name: :index_cost_items_on_spent_on)

    create_if_not_exists table(:daily_energy_summary, primary_key: false) do
      add :date, :string, null: false, primary_key: true
      add :produced_wh, :real, null: false
      add :consumed_wh, :real, null: false
      add :self_consumed_wh, :real, null: false
    end

    # The primary key leads with plug_id although the column comes last; Ecto orders
    # a composite key by column order, so these two tables are plain SQL.
    execute """
    CREATE TABLE IF NOT EXISTS "daily_totals" (
      "date" TEXT NOT NULL,
      "energy_wh" REAL NOT NULL,
      "plug_id" TEXT NOT NULL,
      PRIMARY KEY ("plug_id", "date")
    )
    """

    create_if_not_exists table(:electricity_prices) do
      add :valid_from, :string, null: false
      add :eur_per_kwh, :decimal, precision: 8, scale: 5, null: false
      timestamps(@timestamps)
    end

    create_if_not_exists unique_index(:electricity_prices, [:valid_from],
                           name: :index_electricity_prices_on_valid_from
                         )

    create_if_not_exists table(:lights) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :sku, :string
      add :shelly_plug_id, :string
      add :supports_color, @boolean, default: false, null: false
      add :supports_color_temp, @boolean, default: false, null: false
      timestamps(@timestamps)
      add :firmware_scenes, :text
      add :zones, :text
      add :color_temp_min_k, :integer
      add :color_temp_max_k, :integer
    end

    create_if_not_exists unique_index(:lights, [:key], name: :index_lights_on_key)

    create_if_not_exists table(:light_states) do
      add :light_key, :string, null: false
      add :on, @boolean
      add :brightness, :integer
      add :color_r, :integer
      add :color_g, :integer
      add :color_b, :integer
      add :color_temp_k, :integer
      add :reachable, @boolean
      add :last_seen_at, @datetime
      timestamps(@timestamps)
      add :zone_states, :text
    end

    create_if_not_exists unique_index(:light_states, [:light_key],
                           name: :index_light_states_on_light_key
                         )

    create_if_not_exists table(:plug_states) do
      add :plug_id, :string, null: false
      add :output, @boolean, null: false
      timestamps(@timestamps)
    end

    create_if_not_exists unique_index(:plug_states, [:plug_id],
                           name: :index_plug_states_on_plug_id
                         )

    create_if_not_exists table(:samples, primary_key: false) do
      add :aenergy_wh, :real, null: false
      add :apower_w, :real, null: false
      add :plug_id, :string, null: false, primary_key: true
      add :ts, :bigint, null: false, primary_key: true
    end

    create_if_not_exists index(:samples, [:ts], name: :index_samples_on_ts)

    execute """
    CREATE TABLE IF NOT EXISTS "samples_5min" (
      "avg_power_w" REAL NOT NULL,
      "bucket_ts" INTEGER NOT NULL,
      "energy_delta_wh" REAL NOT NULL,
      "plug_id" TEXT NOT NULL,
      "sample_count" INTEGER NOT NULL,
      PRIMARY KEY ("plug_id", "bucket_ts")
    )
    """

    create_if_not_exists table(:scheduler_states) do
      add :plug_id, :string, null: false
      add :last_tick_at, @datetime, null: false
      timestamps(@timestamps)
    end

    create_if_not_exists unique_index(:scheduler_states, [:plug_id],
                           name: :index_scheduler_states_on_plug_id
                         )

    create_if_not_exists table(:sensor_readings) do
      add :device_id, :string, null: false
      add :taken_at, @datetime, null: false
      add :temperature, :real
      add :humidity, :integer
      add :co2, :integer
      add :battery_pct, :integer
      add :firmware_version, :string
      timestamps(@timestamps)
    end

    create_if_not_exists index(:sensor_readings, [:device_id, :taken_at],
                           name: :index_sensor_readings_on_device_id_and_taken_at
                         )

    create_if_not_exists index(:sensor_readings, [:taken_at],
                           name: :index_sensor_readings_on_taken_at
                         )

    create_if_not_exists table(:solakon_control_states) do
      add :paused, @boolean, default: false, null: false
      timestamps(@timestamps)
      add :decision_state, :string
      add :trim, @boolean, default: false, null: false
      add :last_target_w, :integer
      add :consecutive_failures, :integer, default: 0, null: false
      add :last_decision_at, @datetime
    end

    create_if_not_exists table(:solakon_pv_hours) do
      add :started_at, @datetime, null: false
      add :pv_power_w, :real, null: false
      add :pv1_power_w, :real
      add :pv2_power_w, :real
      add :pv3_power_w, :real
      add :pv4_power_w, :real
      add :reading_count, :integer, null: false
    end

    create_if_not_exists unique_index(:solakon_pv_hours, [:started_at],
                           name: :index_solakon_pv_hours_on_started_at
                         )

    create_if_not_exists table(:solakon_readings) do
      add :taken_at, @datetime, null: false
      add :active_power_w, :real, null: false
      add :pv_power_w, :real, null: false
      add :battery_power_w, :real, null: false
      add :battery_soc_pct, :integer, null: false
      timestamps(@timestamps)
      add :battery_temperature_c, :real
      add :battery_voltage_v, :real
      add :battery_current_a, :real
      add :inverter_temperature_c, :real
      add :status1, :integer
      add :status3, :integer
      add :alarm1, :integer
      add :alarm2, :integer
      add :alarm3, :integer
      add :eps_enabled, @boolean
      add :eps_voltage_v, :real
      add :eps_power_w, :real
    end

    create_if_not_exists index(:solakon_readings, [:taken_at],
                           name: :index_solakon_readings_on_taken_at
                         )

    create_if_not_exists table(:solakon_snapshots) do
      add :taken_at, @datetime, null: false

      for string <- 1..4, quantity <- [:power_w, :voltage_v, :current_a] do
        add :"pv#{string}_#{quantity}", :real
      end

      add :battery_voltage_v, :real
      add :battery_current_a, :real
      add :battery_power_w, :real
      add :battery_soc_pct, :integer
      add :battery_temperature_c, :real
      add :battery_min_temperature_c, :real
      add :battery_health_pct, :integer
      add :remaining_energy_wh, :real
      add :full_charge_capacity_ah, :real
      add :design_energy_wh, :real
      add :inverter_temperature_c, :real
      add :grid_power_w, :real
      add :eps_enabled, @boolean
      add :eps_voltage_v, :real
      add :eps_power_w, :real
      add :status1, :integer
      add :status3, :integer
      add :alarm1, :integer
      add :alarm2, :integer
      add :alarm3, :integer
      add :bms_faults, @json, default: "[]", null: false
      add :pv_total_kwh, :real
      add :battery_charge_total_kwh, :real
      add :battery_discharge_total_kwh, :real
      add :grid_export_total_kwh, :real
      add :grid_import_total_kwh, :real
      timestamps(@timestamps)
      add :active_power_w, :real
    end

    create_if_not_exists index(:solakon_snapshots, [:taken_at],
                           name: :index_solakon_snapshots_on_taken_at
                         )

    create_if_not_exists table(:switch_commands) do
      add :plug_id, :string, null: false
      add :action, :string, null: false
      add :source, :string, null: false
      timestamps(@timestamps)
    end

    create_if_not_exists index(:switch_commands, [:plug_id, :created_at],
                           name: :index_switch_commands_on_plug_id_and_created_at
                         )

    create_if_not_exists table(:switch_rules) do
      add :plug_id, :string, null: false
      add :action, :string, null: false
      add :at_minute, :integer, null: false
      add :days, @json, null: false
      add :enabled, @boolean, default: true, null: false
      add :group_id, :string
      timestamps(@timestamps)
    end

    create_if_not_exists index(:switch_rules, [:plug_id], name: :index_switch_rules_on_plug_id)

    create_if_not_exists unique_index(:switch_rules, [:group_id, :action],
                           name: :index_switch_rules_on_group_id_and_action,
                           where: "group_id IS NOT NULL"
                         )

    create_if_not_exists table(:weather_records) do
      add :kind, :string, null: false
      add :timestamp, @datetime, null: false
      add :lat, :real, null: false
      add :lon, :real, null: false
      add :source_id, :integer
      add :precipitation, :real
      add :pressure_msl, :real
      add :sunshine, :real
      add :temperature, :real
      add :wind_direction, :integer
      add :wind_speed, :real
      add :cloud_cover, :integer
      add :dew_point, :real
      add :relative_humidity, :integer
      add :visibility, :integer
      add :wind_gust_direction, :integer
      add :wind_gust_speed, :real
      add :condition, :string
      add :precipitation_probability, :integer
      add :precipitation_probability_6h, :integer
      add :solar, :real
      add :icon, :string
      add :daytime, :string, null: false
      timestamps(@timestamps)
    end

    create_if_not_exists unique_index(:weather_records, [:kind, :lat, :lon, :timestamp],
                           name: :idx_weather_records_identity
                         )

    create_if_not_exists index(:weather_records, [:kind, :timestamp],
                           name: :idx_weather_records_kind_ts
                         )

    create_if_not_exists index(:weather_records, [:lat, :lon, :timestamp],
                           name: :idx_weather_records_location_ts
                         )
  end

  def down do
    raise Ecto.MigrationError,
          "the baseline is the schema Rails handed over; rolling it back would drop every table"
  end
end
