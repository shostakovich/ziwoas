defmodule Ziwoas.Solakon do
  @moduledoc """
  The read side of the Solakon inverter: status bits decoded into German
  messages (`Solakon::Client.decode_status_messages`). Modbus itself stays in
  Rails until the collector moves (issue #158, Phase 4).
  """
  import Bitwise

  alias Ziwoas.RubyNumeric

  @alarm_bit_labels [
    alarm1: [
      {0, "PV-Spannung zu hoch"},
      {1, "DC-Lichtbogenfehler"},
      {2, "PV-String verpolt"},
      {8, "Netzausfall"},
      {9, "Netzspannung auffällig"},
      {11, "Netzfrequenz auffällig"},
      {14, "Ausgangsstrom zu hoch"},
      {15, "DC-Anteil im Ausgangsstrom zu groß"}
    ],
    alarm2: [
      {0, "Fehlerstrom auffällig"},
      {1, "Erdung auffällig"},
      {2, "Isolationswiderstand zu niedrig"},
      {3, "Temperatur zu hoch"},
      {9, "Energiespeicher auffällig"},
      {10, "Inselbetrieb erkannt"},
      {14, "Außensteckdose überlastet"}
    ],
    alarm3: [
      {3, "Lüfter auffällig"},
      {4, "Energiespeicher verpolt"},
      {9, "Zählerverbindung verloren"},
      {10, "Batteriemanagement nicht erreichbar"}
    ]
  ]

  @doc """
  The messages for a reading's or snapshot's status and alarm registers;
  "Alles ruhig" when nothing is set.
  """
  @spec status_messages(map, [integer]) :: [String.t()]
  def status_messages(registers, bms_faults) do
    status1 = RubyNumeric.to_i(registers.status1)
    status3 = RubyNumeric.to_i(registers.status3)

    status =
      [
        {status1 &&& 0b0001, "Wechselrichter bereit"},
        {status1 &&& 0b0100, "Wechselrichter in Betrieb"},
        {status1 &&& 0b0100_0000, "Wechselrichter meldet Fehler"},
        {status3 &&& 0b0001, "Inselbetrieb aktiv"}
      ]
      |> Enum.filter(fn {bits, _} -> bits > 0 end)
      |> Enum.map(&elem(&1, 1))

    alarms =
      for {key, labels} <- @alarm_bit_labels,
          value = RubyNumeric.to_i(Map.fetch!(registers, key)),
          {bit, label} <- labels,
          (value &&& 1 <<< bit) > 0,
          do: label

    faults =
      if Enum.any?(bms_faults, &(RubyNumeric.to_i(&1) > 0)), do: ["Batterie-Warnung"], else: []

    case status ++ alarms ++ faults do
      [] -> ["Alles ruhig"]
      messages -> messages
    end
  end
end
