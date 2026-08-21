require "mqtt"
require "json"
require "fritz_dect_client"

class FritzMqttBridge
  MAX_BACKOFF_SECONDS = 60

  def initialize(fritz_client:, plug:, mqtt_config:, fritz_poll_cfg:, logger:,
                 mqtt_factory: nil, backoff_seconds: 1)
    @fritz_client   = fritz_client
    @plug           = plug
    @mqtt_config    = mqtt_config
    @fritz_poll_cfg = fritz_poll_cfg
    @logger         = logger
    @backoff_start  = backoff_seconds
    @stopping       = false
    @last_apower_w  = 0.0
    @mqtt_factory   = mqtt_factory || -> {
      MQTT::Client.new(host: @mqtt_config.host, port: @mqtt_config.port)
    }
  end

  def run
    @backoff = @backoff_start
    until @stopping
      begin
        connect_and_poll
      rescue MQTT::Exception, StandardError => e
        # MQTT::Exception descends from ::Exception, so StandardError alone misses it.
        @logger.error("FritzMqttBridge #{@plug.id}: #{e.class}: #{e.message}")
        sleep_interruptible(@backoff) unless @stopping
        @backoff = [ @backoff * 2, MAX_BACKOFF_SECONDS ].min
      end
    end
  end

  def stop!
    @stopping = true
  end

  def poll_and_publish(mqtt)
    reading = @fritz_client.fetch(@plug)
    @last_apower_w = reading.apower_w
    payload = JSON.generate({ apower: reading.apower_w, aenergy: { total: reading.aenergy_wh } })
    mqtt.publish("#{@mqtt_config.topic_prefix}/#{@plug.id}/status/switch:0", payload)
  rescue FritzDectClient::Error => e
    @logger.warn("FritzMqttBridge #{@plug.id}: #{e.message}")
  end

  def interval
    @last_apower_w > @fritz_poll_cfg.idle_threshold_w ?
      @fritz_poll_cfg.active_interval_seconds :
      @fritz_poll_cfg.idle_interval_seconds
  end

  private

  def connect_and_poll
    mqtt = @mqtt_factory.call
    mqtt.connect
    @backoff = @backoff_start
    until @stopping
      poll_and_publish(mqtt)
      sleep_interruptible(interval)
    end
  ensure
    begin; mqtt&.disconnect; rescue StandardError; nil; end
  end

  def sleep_interruptible(seconds)
    deadline = Time.now + seconds
    while Time.now < deadline && !@stopping
      sleep([ deadline - Time.now, 1 ].min)
    end
  end
end
