class Collector
  JOIN_TIMEOUT_SECONDS = 5

  Component = Struct.new(:name, :runnable, keyword_init: true)

  def initialize(config:, logger:, components: nil, join_timeout: JOIN_TIMEOUT_SECONDS)
    @logger       = logger
    @join_timeout = join_timeout
    @components   = components || Assembly.new(config: config, logger: logger).components
    @shutdown     = Queue.new
  end

  def run
    @threads = @components.map { |component| start(component) }
    @logger.info("ziwoas_collector: started #{@threads.length} threads")
    @shutdown.pop
    @logger.info("ziwoas_collector: stopping")
    @components.each { |component| stop(component) }
    join_or_kill
    @logger.info("ziwoas_collector: stopped")
  end

  # Only enqueues, so this stays safe inside a signal handler.
  def stop!
    @shutdown.push(:stop)
  end

  private

  def start(component)
    Thread.new do
      Thread.current.name = component.name
      component.runnable.run
    rescue Exception => e
      # Exception, not StandardError, because MQTT::Exception descends from it.
      # Unrescued, Thread#join would re-raise here and skip every later thread.
      @logger.error("ziwoas_collector: #{component.name} died: #{e.class}: #{e.message}")
    end
  end

  def stop(component)
    component.runnable.stop!
  rescue Exception => e
    # Without this the components after it would never be stopped, nor any thread joined.
    @logger.error("ziwoas_collector: #{component.name} failed to stop: #{e.class}: #{e.message}")
  end

  def join_or_kill
    @threads.each do |thread|
      next if thread.join(@join_timeout)
      # Some blocking MQTT/IO reads don't unwind on disconnect.
      @logger.warn("ziwoas_collector: force-killing #{thread.name}")
      thread.kill
    end
  end
end
