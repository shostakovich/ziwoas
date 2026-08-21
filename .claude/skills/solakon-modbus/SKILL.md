---
name: solakon-modbus
description: Modbus registers, scaling factors, alarms, grid codes and remote control of the Solakon ONE inverter in ZiWoAS. Use for anything touching Solakon, the inverter, the battery, SoC, zero export, Modbus registers, rmodbus or lib/solakon_client.rb — instead of re-parsing the PDF or guessing register addresses.
---

# Solakon ONE – Modbus

The full reference is [`docs/solakon-modbus-protokoll.md`](../../../docs/solakon-modbus-protokoll.md)
(608 lines, German). It merges the official PDF "Solakon ONE Modbus Protokoll v.02/26" with how
[`lib/solakon_client.rb`](../../../lib/solakon_client.rb) actually uses it.

**Never derive register addresses, factors or bit layouts from memory or from the PDF — always
look them up in that file.** The PDF is not in the repo; the reference is the source of truth
for the code.

## Which section to read

Read the relevant section, not the whole file:

| Question | Section |
| --- | --- |
| Which registers do we read/write at all? | 2. Cross-reference: our registers ↔ PDF |
| Where does the code deviate from the PDF? | 3. Deviations & gaps |
| Data types, endianness, scaling, function codes | 4. Fundamentals & terms |
| Measurements (PV, grid, load, battery, meter/CT) | 6., tables 2-4 and 2-5 |
| Cumulative energy counters | 6., table 2-6 |
| Charge/discharge limits, SoC bounds, time windows | 6., tables 2-9 and 2-10 |
| Work mode, grid dispatch, system time | 6., table 2-11 |
| Decoding alarm bits | 7. Alarms (39067–39069) |
| Grid code values | 8. Grid codes |
| Controlling the battery / zero export | 9. Remote control (46001) |

## Verified hardware facts

Confirmed on the device, on top of the reference:

- `battery_power` **negative = discharging**, positive = charging.
- `pv_total_energy` is a **lifetime counter**; low values mean "the unit is new", not
  "measurement error".

## Changing the client

When you change `lib/solakon_client.rb` and add, remove or rescale a register: **update the
cross-reference table in section 2** and record any newly found deviation from the PDF in
section 3. Otherwise the reference drifts from reality and loses exactly the value it exists for.
