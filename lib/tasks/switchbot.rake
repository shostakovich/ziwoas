# lib/tasks/switchbot.rake
require "switch_bot_client"
require "config_loader"

namespace :switchbot do
  desc "List all SwitchBot devices and emit a config snippet for ziwoas.yml"
  task list_devices: :environment do
    path   = Rails.root.join("config", "ziwoas.yml").to_s
    config = ConfigLoader.load(path)

    if config.switchbot.nil?
      abort "switchbot: token/secret missing in config/ziwoas.yml. Add a 'switchbot:' block first."
    end

    client  = SwitchBotClient.new(token: config.switchbot.token, secret: config.switchbot.secret)
    all     = client.list_all_devices
    sensors = client.list_sensor_devices

    puts ""
    puts "Gefundene Geräte:"
    puts "─" * 60
    all.each do |d|
      tag = sensors.any? { |s| s[:id] == d[:id] } ? "" : "(kein Sensor)"
      puts "  #{d[:id].ljust(16)}  #{d[:name].to_s.ljust(20)}  #{d[:device_type].ljust(20)} #{tag}"
    end
    puts "─" * 60

    if sensors.empty?
      puts ""
      puts "Keine Meter Pro CO2 oder Outdoor Meter gefunden."
      next
    end

    puts ""
    puts "Konfigurations-Vorschlag für config/ziwoas.yml:"
    puts ""
    puts "sensors:"
    sensors.each do |s|
      puts "  - id: \"#{s[:id]}\""
      puts "    name: \"#{s[:name]}\""
      puts "    type: #{s[:type]}"
      puts "    room: \"#{s[:name]}\"     # ggf. anpassen" if s[:type] == :meter_pro_co2
      puts ""
    end
  end
end
