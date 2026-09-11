module Solakon
  module Control
    # Singleton row holding the control loop's runtime state: the user-facing
    # pause switch plus what the last tick wrote. It lives here and not in
    # Rails.cache because the policy regulates against it — losing it silently
    # would change how the loop behaves. The row stores and hands back; what the
    # stored decision is still worth is decided by the tick.
    class State < ApplicationRecord
      self.table_name = "solakon_control_states"

      def self.current
        first_or_create!
      end

      def auto_regulation_active?
        !paused?
      end

      def pause_auto_regulation!
        update!(paused: true)
      end

      def resume_auto_regulation!
        update!(paused: false, **CLEARED)
      end

      # What the last tick wrote, or nil before the first one. target_w is the
      # target the inverter actually received — the trim loop integrates against
      # what the device got, not against an intention.
      def stored
        return nil if decision_state.blank? || last_decision_at.blank?

        Stored.new(decision_state: decision_state.to_sym, target_w: last_target_w,
                   trim: trim, at: last_decision_at)
      end

      def store!(decision, at:)
        update!(decision_state: decision.state.to_s, trim: !!decision.trim,
                last_target_w: decision.target_w, last_decision_at: at)
      end

      def clear!
        update!(**CLEARED)
      end

      def failures = consecutive_failures

      def reset_failures!
        update!(consecutive_failures: 0) unless consecutive_failures.zero?
      end

      # Increments and returns the new count.
      def count_failure!
        update!(consecutive_failures: consecutive_failures + 1)
        consecutive_failures
      end

      CLEARED = { decision_state: nil, trim: false, last_target_w: nil, last_decision_at: nil }.freeze
      private_constant :CLEARED
    end
  end
end
