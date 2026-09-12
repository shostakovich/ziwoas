module Solakon
  module Control
    module Types
      include Dry.Types()

      Watt = Dry::Types["coercible.float"]

      # Absent would read as 0 W, which tells the policy the household draws nothing.
      MeasuredWatt = Watt.optional

      TargetW = Dry::Types["coercible.integer"].optional

      # Without the enum, any symbol read back from the row falls through the
      # policy's case into :normal.
      DecisionState = Dry::Types["symbol"].enum(
        :normal, :surplus, :surplus_exhausted, :probe, :probe_blocked, :protected
      )
    end
  end
end
