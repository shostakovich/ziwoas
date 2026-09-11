require "solakon_client"

# Singleton row holding the zero-export control loop's runtime state: the
# user-facing pause switch plus what the last tick decided and wrote. The loop
# state lives here (not in Rails.cache) because the controller regulates
# against it — losing it silently would change control behaviour.
class SolakonControlState < ApplicationRecord
  def self.current
    first_or_create!
  end

  def auto_regulation_active?
    !auto_regulation_paused?
  end

  def pause_auto_regulation!
    update!(auto_regulation_paused: true)
  end

  def resume_auto_regulation!
    update!(auto_regulation_paused: false, control_state: nil, trim: false,
            last_target_w: nil, last_decision_at: nil)
  end

  # The previous tick's decision, or nil before the first tick. target_w is the
  # target actually written to the inverter — the trim loop integrates against
  # what the device got, not against an intention.
  def last_decision(at: Time.current)
    return nil if control_state.blank? || last_decision_at.blank?
    return nil if last_decision_at <= at - SolakonClient::REMOTE_TIMEOUT_S.seconds

    ZeroExportController::Decision.new(state: control_state.to_sym, target_w: last_target_w, trim: trim)
  end

  def remember_decision!(decision, at: Time.current)
    update!(control_state: decision.state.to_s, trim: !!decision.trim,
            last_target_w: decision.target_w, last_decision_at: at)
  end

  def reset_decision!
    update!(control_state: nil, trim: false, last_target_w: nil, last_decision_at: nil)
  end

  def reset_failures!
    update!(consecutive_failures: 0) unless consecutive_failures.zero?
  end

  # Increments and returns the new count.
  def register_failure!
    update!(consecutive_failures: consecutive_failures + 1)
    consecutive_failures
  end
end
