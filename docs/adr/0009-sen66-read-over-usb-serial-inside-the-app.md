# The SEN66 is read over USB serial inside the app

The SEN66 room-air sensor sits on an RP2040 board (firmware in `ziwoas-airquality`) that writes
one JSON line per minute over USB CDC. The repo's Rust bridge to MQTT never ran in production,
and since ADR-0008 there is no broker left. The board hangs on the home server's USB, so
ZiWoAS reads the serial port itself, one process per configured `sen66` sensor.

- **OTP only**: a port runs `stty raw -echo` and `cat` on the device; no serial library, no new
  dependency. The script kills `cat` once its stdin closes, so neither a closed port nor a dead
  BEAM leaves a reader behind, and it ends when `cat` does, so an unplugged board ends the port.
  The process then reopens it with backoff (1 s to 60 s).
- **The firmware's line protocol is the contract** (`ziwoas-airquality/SPEC.md`). The configured
  `id` is the SEN66 serial; lines from any other device are logged and dropped.
- **One row per measurement** in `sensor_readings`, stamped on arrival to the second. Nothing is
  condensed, and the port's state is not stored: a stale reading is the only sign of trouble.

## Consequences

- The container needs the device and a way to see it come back. `devices:` binds the node that
  exists at start only, and the `by-id` links are relative (`../../ttyACM0`), so binding
  `/dev/serial/by-id` alone leaves them dangling. Compose mounts the host's `/dev` read-only at
  `/host-dev` and allows the CDC ACM devices with `device_cgroup_rules: ['c 166:* rmw']`;
  `port:` in `ziwoas.yml` is `/host-dev/serial/by-id/usb-Adafruit_…-if00`, never `ttyACM0`.
- The app's user must be allowed to open the node: the host's `dialout` group (gid 20 on the
  home server) goes into `group_add`.
- The script needs Linux `stty -F` and `cat`, both in the Debian release image's coreutils.
- A room with a SEN66 gets a reading a minute; its room reading counts the SEN66 for 3 minutes,
  then falls back to a SwitchBot sensor in the same room (CONTEXT.md, "Room air").
- No commands go back to the firmware.
