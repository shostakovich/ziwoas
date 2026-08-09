module SwitchRules
  # Pausing and resuming. The caller hands in a scope rather than a record,
  # because both halves of a Zeitfenster always move together.
  class SetEnabled
    def self.call(scope, enabled:)
      scope.update_all(enabled: enabled, updated_at: Time.current)
    end
  end
end
