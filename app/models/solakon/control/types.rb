module Solakon
  module Control
    module Types
      include Dry.Types()

      # Power in watts, however it was counted.
      Watt = Dry::Types["coercible.float"]

      # nil is an answer here, not a missing value: "no fresh measurement".
      # Reading it as 0 W would tell the policy the household draws nothing.
      MeasuredWatt = Watt.optional

      # Watts the inverter is asked to put out. nil before the first tick has
      # written one.
      TargetW = Dry::Types["coercible.integer"].optional

      # The modes the policy moves between. Without the enum any symbol read
      # back from the row falls through the policy's case into :normal.
      DecisionState = Dry::Types["symbol"].enum(
        :normal, :surplus, :surplus_exhausted, :probe, :probe_blocked, :protected
      )
    end
  end
end
