# Supervises the long-running collector components: one thread each, a blocking
# #run that unwinds on #stop!, and a join with a grace period before force-kill.
class Collector
  JOIN_TIMEOUT_SECONDS = 5

  Component = Struct.new(:name, :runnable, keyword_init: true)

  def initialize(config:, logger:, components: nil, join_timeout: JOIN_TIMEOUT_SECONDS)
    @logger       = logger
    @join_timeout = join_timeout
    @components   = components || Assembly.new(config: config, logger: logger).components
    @shutdown     = Queue.new
  end

  # Blocks until #stop! is called, then stops every component and joins its
  # thread.
  def run
    @threads = @components.map { |component| start(component) }
    @logger.info("ziwoas_collector: started #{@threads.length} threads")
    @shutdown.pop # block here until a stop is requested
    @logger.info("ziwoas_collector: stopping")
    @components.each { |component| component.runnable.stop! }
    join_or_kill
    @logger.info("ziwoas_collector: stopped")
  end

  # Only enqueues, so this stays safe inside a signal handler. The teardown runs
  # on the thread that called #run.
  def stop!
    @shutdown.push(:stop)
  end

  private

  # Pass the runnable as a block argument so the thread binds THIS value, not
  # the shared loop variable (which the next iteration would clobber).
  def start(component)
    Thread.new(component.runnable) do |runnable|
      Thread.current.name = component.name
      runnable.run
    rescue Exception => e
      # Everything, because MQTT::Exception inherits from ::Exception rather
      # than StandardError. A component that dies must not take the shutdown
      # with it: Thread#join re-raises here, which would skip every thread
      # after it.
      @logger.error("ziwoas_collector: #{component.name} died: #{e.class}: #{e.message}")
    end
  end

  # Some blocking MQTT/IO reads don't unwind on disconnect, so kill the
  # stragglers to guarantee the process actually exits.
  def join_or_kill
    @threads.each do |thread|
      next if thread.join(@join_timeout)
      @logger.warn("ziwoas_collector: force-killing #{thread.name}")
      thread.kill
    end
  end
end
