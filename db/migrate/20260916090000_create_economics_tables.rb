# The first configuration that lives in the database rather than in
# config/ziwoas.yml: what the plant cost and what a kilowatt-hour costs are
# maintained in the app and change over time (ADR-0004).
class CreateEconomicsTables < ActiveRecord::Migration[8.1]
  def up
    create_table :cost_items do |t|
      t.string  :label,      null: false
      t.decimal :amount_eur, null: false, precision: 10, scale: 2
      t.string  :spent_on,   null: false
      t.string  :note
      t.timestamps
    end
    add_index :cost_items, :spent_on

    create_table :electricity_prices do |t|
      t.string  :valid_from,  null: false
      t.decimal :eur_per_kwh, null: false, precision: 8, scale: 5
      t.timestamps
    end
    add_index :electricity_prices, :valid_from, unique: true

    seed_price_from_yaml
  end

  def down
    drop_table :electricity_prices
    drop_table :cost_items
  end

  private

  # The price used to be a single YAML key. Carry it over as the first price so
  # that savings keep their value across the move; its date is the first day on
  # record, and PriceBook stretches it backwards from there anyway.
  def seed_price_from_yaml
    price = yaml_price
    return if price.nil?

    valid_from = DailyEnergySummary.minimum(:date) || Date.current.to_s
    execute(<<~SQL.squish)
      INSERT INTO electricity_prices (valid_from, eur_per_kwh, created_at, updated_at)
      VALUES (#{connection.quote(valid_from)}, #{connection.quote(price)},
              #{connection.quote(Time.current)}, #{connection.quote(Time.current)})
    SQL
  end

  def yaml_price
    path = Rails.root.join("config", Rails.env.test? ? "ziwoas.test.yml" : "ziwoas.yml")
    return nil unless File.exist?(path)

    raw = YAML.safe_load_file(path)
    value = raw.is_a?(Hash) ? raw["electricity_price_eur_per_kwh"] : nil
    value.is_a?(Numeric) && value.positive? ? value : nil
  rescue Psych::Exception
    nil
  end
end
