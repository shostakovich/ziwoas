class EnergyFlow < Dry::Struct
  module Types
    include Dry.Types()

    Watt    = Dry::Types["coercible.float"].optional
    Percent = Dry::Types["coercible.integer"].optional
    Label   = Dry::Types["coercible.string"].optional
    Flag    = Dry::Types["strict.bool"]
  end

  class Flows < Dry::Struct
    attribute :solar_to_home_w,    Types::Watt
    attribute :solar_to_grid_w,    Types::Watt
    attribute :solar_to_battery_w, Types::Watt
    attribute :grid_to_home_w,     Types::Watt
    attribute :grid_to_battery_w,  Types::Watt
    attribute :battery_to_home_w,  Types::Watt

    def self.unknown = new(**attribute_names.index_with { nil })

    # One missing input makes every flow unknown: a partial split would read as
    # measured zeroes.
    def self.split(home_w:, solar_w:, battery_w:, grid_w:)
      return unknown if [ home_w, solar_w, battery_w, grid_w ].any?(&:nil?)

      home    = [ home_w.to_f, 0.0 ].max
      solar   = [ solar_w.to_f, 0.0 ].max
      battery = battery_w.to_f
      grid    = grid_w.to_f

      grid_import     = [ grid, 0.0 ].max
      solar_to_grid   = [ -grid, 0.0 ].max
      grid_to_home    = [ grid_import, home ].min
      home_remaining  = [ home - grid_to_home, 0.0 ].max
      solar_remaining = [ solar - solar_to_grid, 0.0 ].max

      solar_to_home = [ solar_remaining, home_remaining ].min
      solar_remaining -= solar_to_home
      home_remaining  -= solar_to_home

      if battery.positive?
        solar_to_battery = solar_remaining
        grid_to_battery  = [ grid_import - grid_to_home, [ battery - solar_to_battery, 0.0 ].max ].min
        battery_to_home  = 0.0
      else
        solar_to_battery = 0.0
        grid_to_battery  = 0.0
        battery_to_home  = [ -battery, home_remaining ].min
      end

      new(
        solar_to_home_w:    solar_to_home.round(1),
        solar_to_grid_w:    solar_to_grid.round(1),
        solar_to_battery_w: solar_to_battery.round(1),
        grid_to_home_w:     grid_to_home.round(1),
        grid_to_battery_w:  grid_to_battery.round(1),
        battery_to_home_w:  battery_to_home.round(1)
      )
    end
  end

  attribute :solakon_online,  Types::Flag
  attribute :home_w,          Types::Watt
  attribute :solakon_ac_w,    Types::Watt
  attribute :solar_w,         Types::Watt
  attribute :battery_soc_pct, Types::Percent
  attribute :battery_w,       Types::Watt
  attribute :battery_state,   Types::Label
  attribute :grid_w,          Types::Watt
  attribute :flows,           Flows

  def self.build(home_w:, reading:)
    solar_w   = reading&.pv_power_w
    battery_w = reading&.battery_display_power_w
    grid_w    = home_w && reading ? home_w - reading.active_power_w : nil

    new(
      solakon_online:  !reading.nil?,
      home_w:          home_w,
      solakon_ac_w:    reading&.active_power_w,
      solar_w:         solar_w,
      battery_soc_pct: reading&.battery_soc_pct,
      battery_w:       battery_w,
      battery_state:   reading&.battery_state,
      grid_w:          grid_w,
      flows:           Flows.split(home_w: home_w, solar_w: solar_w,
                                   battery_w: battery_w, grid_w: grid_w)
    )
  end
end
