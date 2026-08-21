require "mqtt_router"
require "shelly_status_handler"
require "govees/subscriber"
require "govees/bridge"
require "govees/platform_api"
require "fritz_mqtt_bridge"
require "fritz_dect_client"

class Collector
  # Turns the ziwoas.yml config into the components the collector supervises.
  # No threads and no I/O: every collaborator here is inert until #run.
  class Assembly
    def initialize(config:, logger:)
      @config = config
      @logger = logger
    end

    def components
      [ router_component ] + govee_components + fritz_components
    end

    private

    def router_component
      handlers = [
        ShellyStatusHandler.new(mqtt_config: @config.mqtt, plugs: @config.plugs, logger: @logger),
        Govees::Subscriber.new(logger: @logger)
      ]
      component("mqtt_router", MqttRouter.new(mqtt_config: @config.mqtt, handlers: handlers, logger: @logger))
    end

    def govee_components
      return [] unless @config.govee
      unless @config.govee.api_key.present?
        @logger.warn("Govees bridge disabled: missing govee.api_key in ziwoas.yml")
        return []
      end

      api = Govees::PlatformApi.new(api_key: @config.govee.api_key)
      [ component("govees_bridge", Govees::Bridge.new(
        mqtt_config: @config.mqtt, govee_config: @config.govee, api: api, logger: @logger,
      )) ]
    end

    def fritz_components
      plugs = @config.plugs.select { |plug| plug.driver == :fritz_dect }
      return [] if plugs.empty?

      client = fritz_client
      plugs.map do |plug|
        component("fritz_bridge_#{plug.id}", FritzMqttBridge.new(
          fritz_client:   client,
          plug:           plug,
          mqtt_config:    @config.mqtt,
          fritz_poll_cfg: @config.fritz_poll,
          logger:         @logger,
        ))
      end
    end

    def fritz_client
      FritzDectClient.new(
        host:     @config.fritz_box.host,
        user:     @config.fritz_box.user,
        password: @config.fritz_box.password,
        timeout:  @config.fritz_poll.timeout_seconds,
      )
    end

    def component(name, runnable) = Component.new(name: name, runnable: runnable)
  end
end
