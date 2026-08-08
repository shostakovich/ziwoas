module SwitchRules
  # Pausing and resuming. Both halves of a Zeitfenster move together — there is
  # no way to pause one — so the caller hands in a scope, not a record: the two
  # rules of a group, or the one rule of an Einzelschaltung.
  #
  # This runs past the form contract on its own member route: a toggle sends one
  # boolean and would fall through a contract that demands times and weekdays.
  class SetEnabled
    def self.call(scope, enabled:)
      scope.update_all(enabled: enabled, updated_at: Time.current)
    end
  end
end
