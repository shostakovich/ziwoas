module Solakon
  module Control
    # A row and not Rails.cache: the policy regulates against what is stored here,
    # so losing it silently would change how the loop behaves.
    class State < ApplicationRecord
      self.table_name = "solakon_control_states"

      def self.current
        first_or_create!
      end

      def active?
        !paused?
      end

      def pause!
        update!(paused: true)
      end

      def resume!
        update!(paused: false, **CLEARED)
      end

      def stored
        return nil if decision_state.blank? || last_decision_at.blank?

        Stored.new(decision_state: decision_state.to_sym, target_w: last_target_w,
                   trim: trim, at: last_decision_at)
      end

      def store!(decision, at:)
        update!(decision_state: decision.state.to_s, trim: decision.trim,
                last_target_w: decision.target_w, last_decision_at: at)
      end

      def clear!
        update!(**CLEARED)
      end

      def failures = consecutive_failures

      def reset_failures!
        update!(consecutive_failures: 0) unless consecutive_failures.zero?
      end

      def count_failure!
        update!(consecutive_failures: consecutive_failures + 1)
        consecutive_failures
      end

      CLEARED = { decision_state: nil, trim: false, last_target_w: nil, last_decision_at: nil }.freeze
      private_constant :CLEARED
    end
  end
end
