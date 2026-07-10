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
    update!(auto_regulation_paused: false)
  end

  # The previous tick's decision, or nil before the first tick. target_w is the
  # target actually written to the inverter — the trim loop integrates against
  # what the device got, not against an intention.
  def last_decision
    return nil if control_state.blank?

    ZeroExportController::Decision.new(state: control_state.to_sym, target_w: last_target_w, trim: trim)
  end

  def remember_decision!(decision)
    update!(control_state: decision.state.to_s, trim: !!decision.trim, last_target_w: decision.target_w)
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
