module Solakon
  module Control
    Outcome = Data.define(:status, :decision, :load, :reading, :failures, :error) do
      def self.applied(decision:, load:, reading:)
        new(status: :applied, decision: decision, load: load, reading: reading, failures: 0, error: nil)
      end

      def self.paused
        new(status: :paused, decision: nil, load: nil, reading: nil, failures: 0, error: nil)
      end

      def self.failed(failures:, error:)
        new(status: :failed, decision: nil, load: nil, reading: nil, failures: failures, error: error)
      end

      def self.released(failures:, error:)
        new(status: :released, decision: nil, load: nil, reading: nil, failures: failures, error: error)
      end

      def applied? = status == :applied

      def log_level = status == :applied || status == :paused ? :info : :warn

      def log_line
        case status
        when :applied  then applied_line
        when :paused   then "runtime paused"
        when :failed   then failure_line
        when :released then "#{failure_line} — relinquished remote control"
        end
      end

      private

      def applied_line
        "state=#{decision.state} target=#{decision.target_w}W load=#{measured_load} " \
        "floor=#{load.floor_w.round}W " \
        "soc=#{reading.battery_soc_pct}% temp=#{reading.battery_temperature_c}C " \
        "pv=#{reading.pv_power_w}W battery=#{reading.battery_power_w}W"
      end

      def measured_load = load.current_w.nil? ? "stale" : "#{load.current_w.round}W"

      def failure_line = "Modbus failure #{failures}/#{Tick::MAX_CONSECUTIVE_FAILURES}: #{error}"
    end
  end
end
