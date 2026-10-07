# Solakon ONE – Modbus protocol (reference)

> A complete write-up of the vendor PDF **"Solakon ONE Modbus Protokoll v.02/26"**
> ([source](https://cdn.shopify.com/s/files/1/0605/9684/6744/files/Solakon_ONE_Modbus_Protokoll_02_26.pdf))
> **plus** a cross-reference with our source code.
>
> **Purpose:** This file is the single source of truth, so the PDF does not have to be
> read and parsed again every time. If the protocol or our use of it changes, update it
> here. As of: 2026-06-20.

## Contents

1. [How we use the protocol (code view)](#1-how-we-use-the-protocol-code-view)
2. [Cross-reference: our registers ↔ PDF](#2-cross-reference-our-registers--pdf)
3. [Deviations & gaps between code and PDF](#3-deviations--gaps-between-code-and-pdf)
4. [Basics & terms (Table 1-1)](#4-basics--terms-table-1-1)
5. [Product parameters (Tables 2-1 to 2-3)](#5-product-parameters-tables-2-1-to-2-3)
6. [Register definition tables (2-4 to 2-11)](#6-register-definition-tables-2-4-to-2-11)
7. [Alarms (Table 3-1)](#7-alarms-table-3-1)
8. [Grid codes (Table 3-2)](#8-grid-codes-table-3-2)
9. [Control (Remote Control 46001)](#9-control-remote-control-46001)

---

## 1. How we use the protocol (code view)

**Transport / connection** — implemented in [`lib/ziwoas/solakon/`](../lib/ziwoas/solakon/) (`Modbus`, `Monitor`, `Client`):

| Property | Value | Source |
|-------------|------|--------|
| Transport | **Modbus TCP** | `Ziwoas.Solakon.Modbus` ([modbus.ex](../lib/ziwoas/solakon/modbus.ex), `:gen_tcp`); one persistent connection in `Ziwoas.Solakon.Monitor` ([monitor.ex](../lib/ziwoas/solakon/monitor.ex)) |
| Register type | **Holding Registers** (FC03 read / FC06 + FC16 write) | `Modbus.read_holding_registers/6`, `write_single_register/6`, `write_multiple_registers/6` |
| Word order (32-bit) | **Big-endian, high word first** | `Client.decode/2` / `Client.from_i32/1` ([client.ex](../lib/ziwoas/solakon/client.ex)) |
| Host | `solakon.host` (e.g. `192.168.1.50`) | [`config/ziwoas.example.yml`](../config/ziwoas.example.yml) |
| Port | `solakon.port`, default **502** | `Ziwoas.Config.Solakon` ([config.ex](../lib/ziwoas/config.ex)) |
| Unit / slave ID | `solakon.unit_id`, default **1** | see above |
| Stale threshold | fixed **120 s**, not configurable | `Ziwoas.Solakon.Reading.stale_after_s/0` |
| Monitoring on? | `solakon.monitoring_enabled`, default **true** | see above |
| Control on? | `solakon.control_enabled`, default **false** | see above |

> **Note on function codes:** The PDF names no FC numbers, unit ID or baud rate (Modbus TCP).
> The values above come from our live-verified code, not from the PDF (see [§3](#3-deviations--gaps-between-code-and-pdf)).

**Data flow** ([`monitor_job.ex`](../lib/ziwoas/solakon/monitor_job.ex) → [`control/tick.ex`](../lib/ziwoas/solakon/control/tick.ex)), every 30 s:

```
Modbus TCP (Solakon ONE)
  → Ziwoas.Solakon.Monitor.read_state           (FC03, via Client.read_state/1)
    → solakon_readings                          (Ziwoas.Solakon.Reading)
    → Ziwoas.Solakon.Control.Tick.run/4         (if control_enabled)
        → Control.LoadReader                    (live load, 24h floor)
        → Control.Policy.decide                 (pure state machine)
        → Monitor.apply_control → Client.apply_control/4  (FC06/FC16, every tick — arms the watchdog)
        → Control.Outcome                       (one answer, which the Monitor logs)
```

Algorithm details: [ADR-0002](adr/0002-solakon-load-following-and-full-battery-surplus.md) and
`Ziwoas.Solakon.Control.Policy` ([policy.ex](../lib/ziwoas/solakon/control/policy.ex)).

---

## 2. Cross-reference: our registers ↔ PDF

The registers used for control. Defined in [`lib/ziwoas/solakon/client.ex`](../lib/ziwoas/solakon/client.ex): read fields in `@fast` (reading, 30 s), `@snapshot_overrides` and `@groups` (snapshot, 2 min), write registers as `@reg_*`. The client also reads status, alarms, temperatures, EPS, energy counters and BMS values; for those, the code is authoritative.

### Read (FC03)

| Address | In code | Model field | Type | #Reg | Scaling in code | PDF entry | Note |
|--------:|----------------|-------------|-----|:----:|--------------------|-------------|-----------|
| 39424 | `battery_soc` | `battery_soc_pct` | i16 | 1 | × 1 (%) | **— not in PDF v02/26 —** | Verified live: returns exactly the same value as BMS1 SoC (37612). Aggregated total SoC; the PDF just does not list it. See [§3](#3-deviations--gaps-between-code-and-pdf). |
| 39248 | `active_power_w` | `active_power_w` | i32 | 2 | × 1 (W) | Index 214 "INV R Phase Active Power" (W, factor 1) | We use the R phase as total active power (single-phase balcony setup). |
| 39230 | `battery_power_w` | `battery_power_w` | i32 | 2 | × 1 (W) | Index 203 "Battery 1 Power" (W, factor 1) | Sign: **+ = charging, − = discharging**. (Combined would be 39237.) |
| 39279 (+2·(n−1)) | `pv_power` (`@groups`) | `pv_power_w` | i32 ×4 | 8 | × 1 (W), sum of the 4 strings | Index 231 ff. "PV1..PVn Power" (W, factor 1) | There is no instantaneous total PV register; unused strings read 0. |
| 37617 | `battery_temperature_c` | `battery_temperature_c` | i16 | 1 | ÷ 10 (°C) | Index 28 "BMS1 Max Temperature" (℃, factor 10) | Scaling matches PDF factor 10. |
| 46609 | `@reg_minimum_soc` | (read only before writing) | u16 | 1 | × 1 (%) | Index 298 "Minimum SoC" (%, [10,100]) | Read only to decide on the self-healing write. |

### Written (FC06 / FC16)

| Address | In code | Type | #Reg | Value | PDF entry | Note |
|--------:|----------------|-----|:----:|------|-------------|-----------|
| 46001 | `@reg_remote_control` | Bitfield16 | 1 | `0b0001` on / `0` off | Index 270 "Remote Control" | `0b0001` = Enable + Generation + Target AC. PDF notation "00 0 1". |
| 46002 | `@reg_remote_timeout` | u16 | 1 | `150` (s) | Index 271 "Remote Timeout_Set" (s) | Inverter-side watchdog; > tick interval, so normal operation never trips it. |
| 46003 | `@reg_remote_active_power` | i32 | 2 | 0…800 (W, clamped) | Index 272 "Remote Control Active Power Command" (W) | Active power setpoint per control tick. |
| 46609 | `@reg_minimum_soc` | u16 | 1 | `10` | Index 298 "Minimum SoC" (%) | Write **only when it differs** (persistent register → spare the flash). |

The `46001` bitfield is encoded in the code as `@remote_control_enable 0b0001`
([client.ex](../lib/ziwoas/solakon/client.ex)). Meaning of the bits → [§9](#9-control-remote-control-46001).

---

## 3. Deviations & gaps between code and PDF

- **SoC register 39424 is missing from PDF v02/26 — but is correct live.** Register definition table 2-5
  ends at the MPPT values (…39337) and then jumps to 39600 (Table 2-6); address **39424** does not exist in
  this document. **Checked live against the device (2026-06-20, host 192.168.8.166):** 39424 returns
  `58 %` — identical to the documented **BMS1 SoC = 37612** (`58 %`). So 39424 is the total SoC aggregated
  by the inverter and a valid source; the PDF just does not list it. The documented fallback would be
  **BMS1 SoC 37612** (or **BMS2 SoC 38310** for the second battery; the test system has only one installed, 38310 = `0`).
- **Active Power (39248).** In the PDF, 39248 is the *INV R Phase* Active Power, not the combined
  active power. For our single-phase setup this is the total power; a three-phase setup
  would have to sum index 214/215/216 or read the combined power (39134, "Active power", kW ×1000).
- **Battery Power (39230).** We read "Battery 1 Power". With two batteries there would be Battery 2 (39235)
  or Battery Combined (39237).
- **Protocol metadata not in the PDF.** Function codes, unit/slave ID, baud rate and explicit endianness
  are **not** in the PDF. The only protocol-level statements: "Register address = 2-byte message",
  "broadcast address = fixed 0", and the version example `0x01020304` = V1.02.03.04 (initial version V1.01.00.00).
  All connection details in [§1](#1-how-we-use-the-protocol-code-view) come from our verified code.

---

## 4. Basics & terms (Table 1-1)

The Modbus protocol is an established device-level communication standard. The Solakon ONE
conforms to the official Modbus specification; the PDF covers only the device-specific parts.

| Term | Meaning |
|---------|-----------|
| master node | Actively initiates communication (master node). |
| slave node | Responds passively to commands (slave node). |
| broadcast address | Fixed to 0. |
| Register address | Corresponds to a 2-byte message. |
| U16 / U32 | 16-bit or 32-bit integer, **unsigned**. |
| I16 / I32 | 16-bit or 32-bit integer, **signed**. |
| STR | Character string. |
| MLD | Multibyte. |
| Bitfield16 / Bitfield32 | 16-bit or 32-bit wide bitwise data representation. |
| s | Second. |
| INV | Inverter. |
| BMS | Battery management system. |
| RO / RW / WO | Read only / read and write / write only. |
| - | Not involved / not applicable. |

**Data type conventions in this file:** "#Reg" = number of 16-bit registers occupied. "Factor" = the value
the raw value is divided by to get the physical unit (e.g. factor 10 for V → raw/10 = volts).

---

## 5. Product parameters (Tables 2-1 to 2-3)

### Table 2-1: Inverter model information

| Index | Signal | Type | Data type | Factor | Address | #Reg |
|------:|--------|-----|----------|:------:|--------:|:----:|
| 1 | Model name | RO | STR | 1 | 30000 | 16 |
| 2 | SN | RO | STR | 1 | 30016 | 16 |
| 3 | MFG ID | RO | STR | 1 | 30032 | 16 |

### Table 2-2: Inverter version information

| Index | Signal | Type | Data type | Address | #Reg |
|------:|--------|-----|----------|--------:|:----:|
| 4 | Master Version | RO | U16 | 36001 | 1 |
| 5 | Slave Version | RO | U16 | 36002 | 1 |
| 6 | Manager Version | RO | U16 | 36003 | 1 |
| 7 | Meter1 SN | RO | STR | 36100 | 16 |
| 8 | Meter1 MFG ID | RO | STR | 36116 | 16 |
| 9 | Meter1 TYPE | RO | STR | 36132 | 16 |
| 10 | Meter1 Version | RO | STR | 36148 | 1 |
| 11 | Meter2 SN | RO | STR | 36200 | 16 |
| 12 | Meter2 MFG ID | RO | STR | 36216 | 16 |
| 13 | Meter2 TYPE | RO | STR | 36232 | 16 |
| 14 | Meter2 Version | RO | STR | 36248 | 1 |

### Table 2-3: Battery version & BMS information

> For BMS1/BMS2: at most 32 slave channels. Channels actually read = "BMS amount of slaves".
> Version address of slave n: `37033 + (n−1)` (BMS1) or `37731 + (n−1)` (BMS2).
> SN address of slave n: `37097 + 16·(n−1)` (BMS1) or `37795 + 16·(n−1)` (BMS2). n ∈ [1, 32].

| Index | Signal | Type | Data type | Unit | Factor | Address | #Reg | Additional info |
|------:|--------|-----|----------|---------|:------:|--------:|:----:|------------|
| 15 | BMS1 connect state | RO | U16 | — | — | 37002 | 1 | 0: Offline, 1: Online |
| 16 | BMS1 Master version | RO | U16 | — | — | 37003 | 1 | |
| 17 | BMS1 Main Control | RO | U16 | — | — | 37004 | 1 | |
| 18 | BMS1 Main SN | RO | STR | — | — | 37005 | 16 | |
| 19 | BMS1 amount of slaves | RO | U16 | — | 1 | 37032 | 1 | [0, 32]; 0 = not present |
| 20 | BMS1 Slave 1 version | RO | U16 | — | — | 37033 | 1 | see formula above |
| 21 | BMS1 Slave 2 version | RO | U16 | — | — | 37034 | 1 | |
| 22 | BMS1 1 - SN | RO | STR | — | — | 37097 | 16 | see formula above |
| 23 | BMS1 2 - SN | RO | STR | — | — | 37113 | 16 | |
| 24 | BMS1 Voltage | RO | U16 | V | 10 | 37609 | 1 | |
| 25 | BMS1 Current | RO | I16 | A | 10 | 37610 | 1 | |
| 26 | BMS1 Ambient Temperature | RO | I16 | ℃ | 10 | 37611 | 1 | |
| 27 | **BMS1 SoC** | RO | U16 | % | 1 | **37612** | 1 | documented SoC source |
| 28 | **BMS1 Max Temperature** | RO | I16 | ℃ | 10 | **37617** | 1 | read by us (`REG_BMS_MAX_TEMP`) |
| 29 | BMS1 Min Temperature | RO | I16 | ℃ | 10 | 37618 | 1 | |
| 30 | BMS1 Max Cell Voltage | RO | U16 | mV | 1 | 37619 | 1 | |
| 31 | BMS1 Min Cell Voltage | RO | U16 | mV | 1 | 37620 | 1 | |
| 32 | BMS1 SOH | RO | U16 | % | 1 | 37624 | 1 | |
| 33–38 | BMS1 Fault1…Fault6 | RO | Bitfield16 | — | — | 37626–37631 | 1 each | |
| 39 | BMS1 Remain Energy | RO | U16 | Wh | 0.1 | 37632 | 1 | |
| 40 | BMS1 FCC Capacity | RO | U16 | Ah | 10 | 37633 | 1 | |
| 41 | reserve | RO | U16 | — | — | 37634 | 1 | |
| 42 | BMS1 Design Energy | RO | U16 | Wh | 0.1 | 37635 | 1 | |
| 43 | BMS1 Force to Change battery Flag | RO | U16 | — | — | 37636 | 1 | 0: Reset, 1: Set (charges until reset) |
| 44 | BMS2 connect state | RO | U16 | — | — | 37700 | 1 | 0: Offline, 1: Online |
| 45 | BMS2 Master version | RO | U16 | — | — | 37701 | 1 | |
| 46 | BMS2 Main control | RO | U16 | — | — | 37702 | 1 | |
| 47 | BMS2 Main SN | RO | STR | — | — | 37703 | 16 | |
| 48 | BMS2 amount of slaves | RO | U16 | — | 1 | 37730 | 1 | [0, 32]; 0 = not present |
| 49 | BMS2 Slave 1 version | RO | U16 | — | — | 37731 | 1 | |
| 50 | BMS2 Slave 2 version | RO | U16 | — | — | 37732 | 1 | |
| 51 | BMS2 1 - SN | RO | STR | — | — | 37795 | 16 | |
| 52 | BMS2 2 - SN | RO | STR | — | — | 37811 | 16 | |
| 53 | BMS2 Voltage | RO | U16 | V | 10 | 38307 | 1 | |
| 54 | BMS2 Current | RO | I16 | A | 10 | 38308 | 1 | |
| 55 | BMS2 Ambient Temperature | RO | I16 | ℃ | 10 | 38309 | 1 | |
| 56 | **BMS2 SoC** | RO | U16 | % | 1 | **38310** | 1 | documented SoC source (2nd battery) |
| 57 | BMS2 Max Temperature | RO | I16 | ℃ | 10 | 38315 | 1 | |
| 58 | BMS2 Min Temperature | RO | I16 | ℃ | 10 | 38316 | 1 | |
| 59 | BMS2 Max Cell Voltage | RO | U16 | mV | 1 | 38317 | 1 | |
| 60 | BMS2 Min Cell Voltage | RO | U16 | mV | 1 | 38318 | 1 | |
| 61 | BMS2 SOH | RO | U16 | % | 1 | 38322 | 1 | |
| 62–67 | BMS2 Fault1…Fault6 | RO | Bitfield16 | — | — | 38324–38329 | 1 each | |
| 68 | BMS2 Remain Energy | RO | U16 | Wh | 0.1 | 38330 | 1 | |
| 69 | BMS2 FCC Capacity | RO | U16 | Ah | 10 | 38331 | 1 | |
| 70 | reserve | RO | U16 | — | — | 38332 | 1 | |
| 71 | BMS2 Design Energy | RO | U16 | Wh | 0.1 | 38333 | 1 | |
| 72 | BMS2 Force to Change battery Flag | RO | U16 | — | — | 38334 | 1 | 0: Reset, 1: Set |

---

## 6. Register definition tables (2-4 to 2-11)

In the PDF, all of these tables carry the title "Register Definitionstabelle". Here they are named
by address range and topic. Where "PVn"/"MPPTn"/"Meter" are generic, the number of channels read = the matching "Number of …".

### Table 2-4: Meter / CT readings (38801–38946)

The address scheme is the same for Meter1/CT1 (388xx) and Meter2/CT2 (389xx). Connect State: U16, 0 = disconnected, 1 = connected.
All other readings: I32, 2 registers.

| Quantity | Unit | Factor | Meter1 address | Meter2 address |
|-------|---------|:------:|:--------------:|:--------------:|
| Connect State (U16) | — | — | 38801 | 38901 |
| R/S/T Phase Voltage | V | 10 | 38802 / 38804 / 38806 | 38902 / 38904 / 38906 |
| R/S/T Phase Current | A | 1000 | 38808 / 38810 / 38812 | 38908 / 38910 / 38912 |
| Combined Active Power | W | 10 | 38814 | 38914 |
| R/S/T Phase Active Power | W | 10 | 38816 / 38818 / 38820 | 38916 / 38918 / 38920 |
| Combined Reactive Power | Var | 10 | 38822 | 38922 |
| R/S/T Phase Reactive Power | Var | 10 | 38824 / 38826 / 38828 | 38924 / 38926 / 38928 |
| Combined Apparent Power | VA | 10 | 38830 | 38930 |
| R/S/T Phase Apparent Power | VA | 10 | 38832 / 38834 / 38836 | 38932 / 38934 / 38936 |
| Combined Power Factor | — | 1000 | 38838 | 38938 |
| R/S/T Phase Power Factor | — | 1000 | 38840 / 38842 / 38844 | 38940 / 38942 / 38944 |
| Freq | Hz | 100 | 38846 | 38946 |

### Table 2-5: Inverter / PV / grid / load / battery readings (39000–39337)

> **Protocol version (39000):** `0x01020304` = V1.02.03.04; initial version V1.01.00.00.
> **PV strings:** `PVn voltage = 39070 + 2·(n−1)`, `PVn current = 39071 + 2·(n−1)`, `PVn Power = 39279 + 2·(n−1)`, n ∈ [1, 24].
> **MPPT:** `MPPTn Volt = 39327 + 4·(n−1)`, `MPPTn Curr = 39328 + 4·(n−1)`, `MPPTn Power = 39329 + 4·(n−1)`, n ∈ [1, 24].

| Index | Signal | Type | Data type | Unit | Factor | Address | #Reg | Additional info |
|------:|--------|-----|----------|---------|:------:|--------:|:----:|------------|
| 121 | Protocol version | RO | U32 | — | — | 39000 | 2 | see example above |
| 122 | Model name | RO | STR | — | 1 | 39002 | 16 | |
| 123 | SN | RO | STR | — | 1 | 39018 | 16 | |
| 124 | PN | RO | STR | — | 1 | 39034 | 16 | |
| 125 | Model ID | RO | U16 | — | 1 | 39050 | 1 | |
| 126 | Number of strings | RO | U16 | — | 1 | 39051 | 1 | |
| 127 | Number of MPPTs | RO | U16 | — | 1 | 39052 | 1 | |
| 128 | Rated power (Pn) | RO | I32 | kW | 1000 | 39053 | 2 | |
| 129 | Maximum active power (Pmax) | RO | I32 | kW | 1000 | 39055 | 2 | |
| 130 | Maximum apparent power (Smax) | RO | I32 | kVA | 1000 | 39057 | 2 | |
| 131 | Max reactive power (Qmax, fed in) | RO | I32 | kVar | 1000 | 39059 | 2 | |
| 132 | Max reactive power (Qmax, drawn) | RO | I32 | kVar | 1000 | 39061 | 2 | |
| 133 | Status 1 | RO | Bitfield16 | — | 1 | 39063 | 1 | Bit0: standby; Bit2: running; Bit6: fault |
| 135 | Status 3 | RO | Bitfield32 | — | 1 | 39065 | 2 | Bit0: off-grid (island) mode (0=no, 1=yes) |
| 136 | Alarm 1 | RO | Bitfield16 | — | 1 | 39067 | 1 | see [§7](#7-alarms-table-3-1) |
| 137 | Alarm 2 | RO | Bitfield16 | — | 1 | 39068 | 1 | see [§7](#7-alarms-table-3-1) |
| 138 | Alarm 3 | RO | Bitfield16 | — | 1 | 39069 | 1 | see [§7](#7-alarms-table-3-1) |
| 139 | PV1 voltage | RO | I16 | V | 10 | 39070 | 1 | scheme see above |
| 140 | PV1 current | RO | I16 | A | 100 | 39071 | 1 | |
| 141–146 | PV2…PV4 voltage/current | RO | I16 | V / A | 10 / 100 | 39072–39077 | 1 each | |
| 147 | Total PV input power | RO | I32 | kW | 1000 | 39118 | 2 | |
| 151–153 | Grid R/S/T phase voltage | RO | I16 | V | 10 | 39123 / 39124 / 39125 | 1 each | |
| 154–156 | Inverter R/S/T phase current | RO | I32 | A | 1000 | 39126 / 39128 / 39130 | 2 each | |
| 158 | Active power | RO | I32 | kW | 1000 | 39134 | 2 | combined active power |
| 159 | Reactive power | RO | I32 | kVar | 1000 | 39136 | 2 | |
| 160 | power factor | RO | I16 | — | 1000 | 39138 | 1 | |
| 161 | Grid frequency | RO | I16 | Hz | 100 | 39139 | 1 | |
| 163 | internal temperature | RO | I16 | ℃ | 10 | 39141 | 1 | |
| 169 | Cumulative power generation | RO | U32 | kWh | 100 | 39149 | 2 | |
| 170 | Power generation on the day | RO | U32 | kWh | 100 | 39151 | 2 | |
| 178 | Energy storage module 1 charge/discharge power | RO | I32 | W | 1 | 39162 | 2 | >0: charging, <0: discharging |
| 181 | Meter collection Active power | RO | I32 | W | 1 | 39168 | 2 | >0: feed-in, <0: grid import |
| 186–188 | EPS R/S/T Phase Voltage | RO | U16 | V | 10 | 39201 / 39202 / 39203 | 1 each | |
| 189–191 | EPS R/S/T Phase Current | RO | I32 | A | 1000 | 39204 / 39206 / 39208 | 2 each | |
| 192–194 | EPS R/S/T Phase Power | RO | I32 | W | 1 | 39210 / 39212 / 39214 | 2 each | |
| 195 | EPS Combined Power | RO | I32 | W | 1 | 39216 | 2 | |
| 196 | EPS Frequency | RO | I16 | Hz | 100 | 39218 | 1 | |
| 197–199 | Load R/S/T Phase Power | RO | I32 | W | 1 | 39219 / 39221 / 39223 | 2 each | |
| 200 | Load Combined Power | RO | I32 | W | 1 | 39225 | 2 | |
| 201 | Battery1 Voltage | RO | I16 | V | 10 | 39227 | 1 | |
| 202 | Battery1 Current | RO | I32 | A | 1000 | 39228 | 2 | |
| 203 | **Battery 1 Power** | RO | I32 | W | 1 | **39230** | 2 | read by us (`REG_BATTERY_POWER`) |
| 204 | Battery 2 Voltage | RO | I16 | V | 10 | 39232 | 1 | |
| 205 | Battery 2 Current | RO | I32 | A | 1000 | 39233 | 2 | |
| 206 | Battery 2 Power | RO | I32 | W | 1 | 39235 | 2 | |
| 207 | Battery Combined Power | RO | I32 | W | 1 | 39237 | 2 | |
| 214–216 | **INV R/S/T Phase Active Power** | RO | I32 | W | 1 | **39248** / 39250 / 39252 | 2 each | R phase = `REG_ACTIVE_POWER` |
| 218–220 | INV R/S/T Phase Reactive Power | RO | I32 | Var | 1 | 39256 / 39258 / 39260 | 2 each | |
| 222–224 | INV R/S/T Phase Apparent Power | RO | I32 | VA | 1 | 39264 / 39266 / 39268 | 2 each | |
| 225 | INV Combined Apparent Power | RO | I32 | VA | 1 | 39270 | 2 | |
| 226–228 | INV Frequency R/S/T | RO | I16 | Hz | 100 | 39272 / 39273 / 39274 | 1 each | |
| 229 | Available Import Power | RO | I32 | W | 1 | 39275 | 2 | |
| 230 | Available Export Power | RO | I32 | W | 1 | 39277 | 2 | |
| 231–234 | **PV1…PV4 Power** | RO | I32 | W | 1 | **39279** / 39281 / 39283 / 39285 | 2 each | summed by us (`REG_PV_POWER_BASE`) |
| 235 | MPPT1 Voltage | RO | I16 | V | 10 | 39327 | 1 | scheme see above |
| 236 | MPPT1 Current | RO | I16 | A | 100 | 39328 | 1 | |
| 237 | MPPT1 Power | RO | I32 | W | 1 | 39329 | 2 | |
| 238–243 | MPPT2/MPPT3 Volt/Curr/Power | RO | I16/I32 | V/A/W | 10/100/1 | 39331–39337 | | |

> Skipped indices (134, 148–150, 157, 162, 164–168, 171–177, 179–180, 182–185, 208–213, 217, 221) are listed as **reserve** in the PDF.
> **Gap:** the PDF documents nothing between 39337 and 39600 (relevant for our SoC register 39424, see [§3](#3-deviations--gaps-between-code-and-pdf)).

### Table 2-6: Cumulative energy counters (39600–39631)

All U32, kWh, factor 100, 2 registers each.

| Index | Signal | Address |
|------:|--------|--------:|
| 245 | PV total power | 39601 |
| 246 | Total PV power today | 39603 |
| 247 | Total charging capacity | 39605 |
| 248 | Today's total charging capacity | 39607 |
| 249 | Total discharge power | 39609 |
| 250 | Today's total discharge power | 39611 |
| 251 | Total power of feeder network (total feed-in) | 39613 |
| 252 | Today's total feeder power | 39615 |
| 253 | Total power taken (total grid import) | 39617 |
| 254 | Today's total electricity consumption | 39619 |
| 255 | Output total power | 39621 |
| 256 | Total power output today | 39623 |
| 257 | Enter total power | 39625 |
| 258 | Enter total power today | 39627 |
| 259 | Total load power | 39629 |
| 260 | Total load power today | 39631 |

### Table 2-7: Battery commands / factory reset (45000–45007)

| Index | Signal | Type | Data type | Address | Values / additional info |
|------:|--------|-----|----------|--------:|--------------------|
| 263 | Factory Reset | WO | U16 | 45002 | 0: invalid, 1: active |
| 264 | Battery power active | WO | U16 | 45003 | 0/1 — H3 Smart series only |
| 266 | Battery power shutdown | WO | U16 | 45005 | 0/1 — H3 Smart series only |
| 267 | Battery power ON/OFF | RO | U16 | 45006 | 0: OFF, 1: ON |
| 268 | Battery Connect Enable | RW | U16 | 45007 | 0: Disable, 1: Enable — H3 Smart series only |

### Table 2-8: Remote control (46000–46020)

| Index | Signal | Type | Data type | Unit | Address | #Reg | Additional info |
|------:|--------|-----|----------|---------|--------:|:----:|------------|
| 270 | Remote Control | RW | Bitfield16 | — | 46001 | 1 | bit layout see [§9](#9-control-remote-control-46001) |
| 271 | Remote Timeout_Set | RW | U16 | s | 46002 | 1 | watchdog window |
| 272 | Remote Control Active Power Command | RW | I32 | W | 46003 | 2 | active power setpoint |
| 273 | Remote Control Reactive Power Command | RW | I32 | Var | 46005 | 2 | reactive power setpoint |
| 274 | Remote Timeout Countdown | RO | U16 | s | 46007 | 1 | remaining active time |
| 275 | Pwr_limit Bat_Up | RO | I32 | W | 46018 | 2 | |
| 276 | Pwr_limit Bat_Dn | RO | I32 | W | 46020 | 2 | |

### Table 2-9: Charge/discharge limits & time windows (46500–46514)

| Index | Signal | Type | Data type | Unit | Address | #Reg |
|------:|--------|-----|----------|---------|--------:|:----:|
| 278 | Import Power Limit | RW | I32 | W | 46501 | 2 |
| 279 | Threshold SOC | RW | U16 | % | 46503 | 1 |
| 280 | Export Peak Limit | RW | I32 | W | 46504 | 2 |
| 281 | ChrInLowImport | RW | U16 | — | 46506 | 1 |
| 282–285 | ChrInLowTime1 Start/End Hour/Minute | RW | U16 | — | 46507–46510 | 1 each |
| 286–289 | ChrInLowTime2 Start/End Hour/Minute | RW | U16 | — | 46511–46514 | 1 each |

### Table 2-10: Battery current limits, SoC limits, EPS (46601–46619)

| Index | Signal | Type | Data type | Unit | Factor | Address | Additional info |
|------:|--------|-----|----------|---------|:------:|--------:|------------|
| 296 | Battery maximum charging current | RW | I16 | A | 10 | 46607 | H3:[0,26]; H3Pro/KH:[0,50]; H1:[0,40]; H1-G2:[0,40] |
| 297 | Battery maximum discharge current | RW | I16 | A | 10 | 46608 | H3:[0,26]; H3Pro/KH:[0,50]; H1:[0,50]; H1-G2:[0,40] |
| 298 | **Minimum SoC** | RW | U16 | % | 1 | **46609** | [10,100] — written by us (`REG_MINIMUM_SOC`) |
| 299 | Maximum SoC | RW | U16 | % | 1 | 46610 | [10,100] |
| 300 | Minimum SoC OnGrid | RW | U16 | % | 1 | 46611 | [10,100] |
| 301 | EPS Frequency Select | RW | U16 | — | — | 46612 | 0: invalid, 1: 50 Hz, 2: 60 Hz |
| 302 | EPS Output | RW | U16 | — | — | 46613 | 0: off, 2: EPS, 3: UPS |
| 303 | Balance Load | RW | U16 | — | — | 46614 | 0: off, 1: on |
| 304 | Balance Logic First | RW | U16 | — | — | 46615 | 0: off, 1: on |
| 305 | Export Power Limit | RW | I32 | W | 1 | 46616 | [0, Pmax] |
| 306 | Import Current Limit | RW | I16 | A | 10 | 46618 | |
| 307 | Export Current Limit | RW | I16 | A | 10 | 46619 | |

### Table 2-11: System time, grid dispatch, work mode, device settings (49000–49245)

| Index | Signal | Type | Data type | Unit | Factor | Address | #Reg | Additional info |
|------:|--------|-----|----------|---------|:------:|--------:|:----:|------------|
| 308 | system time | RW | U32 | — | — | 49000 | 2 | local time [946684800, 3155759999] |
| 312 | Grid Scheduling: Power compensation (PF) | RW | I16 | — | 1000 | 49005 | 1 | (−1, −0.8] ∪ [0.8, 1] |
| 313 | Grid Scheduling: Power compensation (Q/S) | RW | I16 | — | 1000 | 49006 | 1 | [−1.000, +1.000] |
| 314 | Grid dispatch: Active power % derating | RW | I16 | % | 10 | 49007 | 1 | [0, 100.0] |
| 322 | Power on | RW | U16 | — | — | 49077 | 1 | 0: invalid, 1: valid (status: 49228) |
| 323 | Shut down | RW | U16 | — | — | 49078 | 1 | 0: invalid, 1: valid (status: 49228) |
| 324 | Grid standard code | RW | U16 | — | — | 49079 | 1 | see [§8](#8-grid-codes-table-3-2) |
| 335 | Grid point power limit | RW | I32 | W | 1 | 49136 | 2 | [0, Pmax]; default Pmax |
| 341 | Work mode | RW | U16 | — | — | 49203 | 1 | 1: self-consumption; 2: feed-in priority; 3: backup; 4: peak shaving; 6: forced charge; 7: forced discharge |
| 342 | DRM | RW | U16 | — | — | 49206 | 1 | 0/1 (AU only) |
| 343 | Meter1/CT1 | RW | U16 | — | — | 49207 | 1 | 0: off, 1: 1-phase meter, 2: CT, 3: 3-phase meter |
| 344 | Meter2/CT2 | RW | U16 | — | — | 49208 | 1 | 0: off, 1: 1-phase meter, 2: CT, 3: 3-phase meter |
| 345 | BUZZER | RW | U16 | — | — | 49209 | 1 | 0/1 |
| 346 | MPPT Switch | RW | U16 | — | — | 49210 | 1 | 0/1 |
| 347 | Relay1 Switch | RW | U16 | — | — | 49211 | 1 | 0/1 |
| 348 | Relay2 Switch | RW | U16 | — | — | 49212 | 1 | 0/1 |
| 349 | Brightness Level | RW | U16 | % | 1 | 49221 | 1 | 0–100 % |
| 350–355 | Year / Month / Day / Hour / Minute / Second | RW | U16 | — | 1 | 49222–49227 | 1 each | RTC setting |
| 356 | System Power State | RO | U16 | — | 1 | 49228 | 1 | 0: OFF, 1: ON |
| 357 | Idle State | RW | U16 | — | 1 | 49229 | 1 | 0/1 |
| 358 | Idle Loadpower Threshold | RW | U16 | W | 1 | 49230 | 1 | H3: 100–200 W; H3Pro: 100–600 W |
| 359 | Clear Idle Count | WO | U16 | — | 1 | 49231 | 1 | 0: clear idle counter |
| 360 | Key Password | RW | STR | — | 1 | 49232 | 8 | |
| 361 | Network status | RO | U16 | — | 1 | 49240 | 1 | 0: not connected, 1: disconnected, 2: connected |
| 362 | Ripple Control Enable | RW | U16 | — | 1 | 49241 | 1 | 0/1 |
| 363 | Trigger Signal | RO | U16 | — | 1 | 49242 | 1 | Bit0–3: K1–K4 status |
| 364–366 | K1/K2/K3 Power Ratio | RW | U16 | % | 1 | 49243–49245 | 1 each | [0, 100] |

---

## 7. Alarms (Table 3-1)

Source: registers **Alarm 1 = 39067**, **Alarm 2 = 39068**, **Alarm 3 = 39069** (Bitfield16 each).
An empty "Level" means the PDF does not mark the bit "important"; all named bits are "important" unless noted otherwise.

### Alarm 1 (39067)

| Bit | Meaning |
|----:|-----------|
| 0 | Input string voltage too high |
| 1 | DC arc fault |
| 2 | String reverse polarity |
| 8 | Grid power outage |
| 9 | Grid voltage abnormal |
| 11 | Grid frequency abnormal |
| 14 | Output overcurrent |
| 15 | DC component in output current too large |

(Bits 3–7, 10, 12, 13 = reserve.)

### Alarm 2 (39068)

| Bit | Meaning |
|----:|-----------|
| 0 | Residual current abnormal |
| 1 | System grounding abnormal |
| 2 | Insulation resistance too low |
| 3 | Temperature too high |
| 9 | Energy storage device abnormal |
| 10 | Isolated island (islanding) |
| 14 | Off-grid output overloaded |

(Bits 4–8, 11–13, 15 = reserve.)

### Alarm 3 (39069)

| Bit | Meaning | Level |
|----:|-----------|-------|
| 3 | External fan abnormal | important |
| 4 | Energy storage reverse polarity | important |
| 9 | Meter Lost | (not marked) |
| 10 | BMS Lost | (not marked) |

(All other bits = reserve.)

---

## 8. Grid codes (Table 3-2)

Written via **Grid standard code = 49079** (U16). Values (enumeration → standard → country):

| Code | Name | Country |
|----:|------|------|
| 0 | AS4777_AU | Australia |
| 1 | AS4777_NZ | New Zealand |
| 2 | G98_UK | U.K. |
| 3 | G99_UK | U.K. |
| 4 | EN50549_NL | Netherlands |
| 5 | CEI021_A | Italy |
| **6** | **VDE0126** | **Germany** |
| **7** | **VDE4105_DE** | **Germany** |
| 8 | NBR-220_BR | Brazil |
| 9 | NBR-240_BR | Brazil |
| 10 | IEC61727 | India |
| 11 | Philippines | The Philippines |
| 12 | NRS_SA | South Africa |
| 13 | Vietnam | Vietnam |
| 14 | EN50549_PL | Poland |
| 15 | EN50549_PT | Portugal |
| 16 | PPDS_CR | Czech Republic |
| 17 | UNE-206_SP | Spain |
| 18 | RD1699_SP | Spain |
| 19 | Belgium | Belgium |
| 20 | VFR2019_FR | France |
| 21 | UTE_FR | France |
| 22 | Singapore | Singapore |
| 23 | Indonesia | Indonesia |
| 24 | Malaysia | Malaysia |
| 25 | Cambodia | Cambodia |
| 26 | PEA_TH | Thailand |
| 27 | MEA_TH | Thailand |
| 28 | Sri Lanka | Sri Lanka |
| 29 | Pakistan | Pakistan |
| 30 | Ireland | Ireland |
| 31 | Denmark 3.2.1 | Denmark |
| 32 | Slovakia | Slovakia |
| 33 | Austria | Austria |
| 34 | Switzerland | Switzerland |
| 35 | Slovenia | Slovenia |
| 36 | Hungary | Hungary |
| 37 | Serbia | Serbia |
| 38 | Croatia | Croatia |
| 39 | Turkey | Türkiye |
| 40 | Cyprus | Cyprus |
| 41 | Bulgaria | Bulgaria |
| 42 | Romania | Romania |
| 43 | Greece | Greece |
| 44 | Latvia | Latvia |
| 45 | Lithuania | Lithuania |
| 46 | Estonia | Estonia |
| 47 | Sweden | Sweden |
| 48 | Norway | Norway |
| 49 | Finland | Finland |
| 50 | Argentina | Argentina |
| 51 | Chile BT | Chile |
| 52 | Mexico | Mexico |
| 53 | USA | USA |
| 54 | Hawaii | Canada *(sic, as in the original)* |
| 55 | CQC_CN | China |
| 56 | Japan | Japan |
| 57 | CQC_CN-1 | China (wide range) |
| 58 | Local | India (wide range) |
| 59 | Saudi Arabia | Saudi Arabia |
| 60 | AS4777_AU-2020A | Australia (A) |
| 61 | AS4777_AU-2020B | Australia (B) |
| 62 | AS4777_AU-2020C | Australia (C) |
| 63 | AS4777_NZ-2020 | New Zealand |
| 64 | CQC_CN-2 | China (wide range 2) |
| 65 | CEI021_B | Italy |
| 66 | CEI021_Areti_A | Italy |
| 67 | CEI021_Areti_B | Italy |
| 68 | NBR-220_BR2022 | Brazil |
| 69 | Spain | Spain |
| 70 | CQC_CN-3 | China |
| 71 | Puerto Rico | Puerto Rico |
| 72 | G98_NI | Northern Ireland |
| 73 | G99_NI | Northern Ireland |
| 74 | USA-208 | USA |
| **75** | **VDE4110_DE** | **Germany** |
| 76 | KSC8564 | South Korea |
| 77 | KSC8565 | South Korea |
| 78 | PR-LUMA | Puerto Rico |
| 79 | CEI016 | Italy |
| 80 | DUBAI | Dubai |
| 81 | Denmark 3.2.2 | Denmark |
| 82 | TR 3.3.1-DK1 | Denmark |
| 83 | TR 3.3.1-DK2 | Denmark |
| 84 | Chile MT-A | Chile |
| 85 | Chile MT-B | Chile |

---

## 9. Control (Remote Control 46001)

Control runs centrally through the bitfield **46001**, combined with the timeout (46002) and the
power setpoint (46003). Our code sets `46001 = 0b0001` (Enable + Generation + AC).

### Bit layout of 46001

| Bit(s) | Function | Values |
|--------|----------|-------|
| 0 | Enable remote control | 0 = disabled, 1 = enabled |
| 1 | Definition of positive direction | 0 = generation system (Generation), 1 = consumption system (Consumption) |
| 3:2 | Controlled target | 00 = AC, 01 = battery, 10 = grid (CT/meter), 11 = AC (grid first) |
| 15:4 | reserved | — |

> PDF notation of the examples: `[Bits 3:2] [Bit 1] [Bit 0]`, e.g. "00 0 1".

### Use cases from the PDF

| Scenario | 46001 (Bit 3:2 / 1 / 0) | Enable | Direction | Target |
|----------|--------------------------|:------:|----------|--------|
| **PV priority** – charge storage (Generation) | `00 0 1` | 1 | Generation | AC |
| **PV priority** – charge storage (Consumption) | `00 1 1` | 1 | Consumption | AC |
| **Battery priority** – discharge storage | `01 0 1` | 1 | Generation | Battery |
| **Battery priority** – charge storage | `01 1 1` | 1 | Consumption | Battery |
| **Meter** – discharge with smart meter | `10 0 1` | 1 | Generation | Grid |
| **Meter** – charge with smart meter | `10 1 1` | 1 | Consumption | Grid |

### Control sequence in the code

`Ziwoas.Solakon.Client.apply_control/4` ([client.ex](../lib/ziwoas/solakon/client.ex)) writes in this order:

1. **46609** Minimum SoC — *only if it differs* (self-healing, spares the flash).
2. **46001** Remote Control = `0b0001` (Enable, Generation, AC).
3. **46002** Remote Timeout = `150 s` (watchdog re-arm).
4. **46003** active power setpoint (i32, W) — last.

`Client.release_control/1` writes `46001 = 0`, so the inverter falls back to its safe default.
If writing fails, the **device-side watchdog** takes over as a backstop after 150 s.

---

*Generated from the PDF v02/26 + source code as of 2026-06-20. Update this file when the protocol changes (new PDF version).*
