# tpnsfand

Userspace fan control for ThinkPads whose embedded controller (EC) exposes the
fan through **non-standard registers** (the kernel's `thinkpad_acpi`
`TPACPI_FAN_NS` quirk). On these machines the mainline driver can only *read*
the fan speed, not *control* it — so the fan often runs constantly at idle with
no way to slow it down.

`tpnsfand` talks to the EC registers directly: it keeps the fan quiet (or off)
while the machine is cool and hands control back to the EC once things get warm.

Version: 0.1 · License: GPL-2.0-only

---

## ⚠️ Safety / Disclaimer

**This tool writes directly to Embedded Controller registers. Misuse can let
your machine overheat.**

- While `tpnsfand` holds host control, the EC does **not** regulate the fan —
  the only remaining hardware safety net is the CPU's own thermal throttle
  (~100 °C). `tpnsfand` mitigates this with a 0.5-second watchdog loop and by
  handing control back to the EC above a temperature threshold, but there is no
  independent failsafe.
- The register layout, speed range, and EC floor may differ between models.
  Values validated on one machine are not guaranteed correct on another.
- Disabling Secure Boot (a prerequisite, see below) reduces your system's
  security posture.

This program is distributed **without any warranty** (see GPL-2.0-only). Use at your
own risk.

---

## What & Why

The affected ThinkPads use an EC firmware that places the fan status/control and
tacho bytes at non-standard addresses. The kernel recognizes these models and
reports the fan speed correctly, but provides **no write path** — the standard
`fan_control=1` / `/proc/acpi/ibm/fan` interface does nothing, `pwm1_enable`
returns `EPERM`, and the fan keeps spinning at idle (often ~3800–4200 RPM)
regardless of how cool the machine is.

`tpnsfand` fills that gap from userspace.

## How it works

It reads three EC bytes and writes two of them:

| Register | Role |
| --- | --- |
| `0x93` | control byte — `0x04` = EC controls, `0x14` = host (us) controls |
| `0x94` | fan speed command (inverse scale, roughly `RPM ≈ 491520 / value`) |
| `0x95` | tacho, read-only (`RPM ≈ 491520 / value`, saturates near 1927 RPM) |

The daemon regulates on `max(CPU package, NVMe)` temperature and runs a small
state machine with hysteresis:

- **OFF** — below `TEMP_FAN_OFF`: host control, fan commanded off.
- **RAMP** — between the thresholds: host control, fan speed ramped linearly
  from `RPM_LOW` (at `TEMP_FAN_ON`) up to `RPM_HIGH` (at `TEMP_CTRL_EC`).
- **EC** — at/above `TEMP_CTRL_EC`: control handed back to the EC, which runs
  its own (safe) auto curve. Control is taken back below `TEMP_CTRL_HOST`.

Host control is re-asserted every loop (self-heals across suspend/resume), and
on exit the daemon returns control to the EC.

## Requirements

- A ThinkPad with the non-standard EC fan layout (see **Compatibility**).
- `ec_sys` with write support enabled: kernel command line `ec_sys.write_support=1`.
  `ec_sys` may need loading (`sudo modprobe ec_sys`) if it is not built in.
- **Secure Boot disabled.** Secure Boot triggers kernel lockdown (integrity),
  which blocks EC writes even with `write_support=1`.
- `coretemp` (CPU package temperature) and, optionally, `nvme` hwmon sensors.

Enabling `ec_sys.write_support=1` is distro-specific. Add it to your kernel
command line via your bootloader's mechanism (e.g. `/etc/default/grub` +
`update-grub`, or `/etc/kernel/cmdline` + the appropriate regeneration step) and
reboot. Verify:

```bash
cat /sys/module/ec_sys/parameters/write_support   # expect Y
```

## Installation

```bash
git clone https://github.com/h4fnp/tpnsfand
cd tpnsfand
# make sure the prerequisites above are met first
sudo make install
```

`make install` copies the daemon to `/usr/local/sbin`, installs the service,
enables it, and starts it immediately **if** `write_support` is already active
(otherwise it is enabled for the next boot). Verify:

```bash
journalctl -u tpnsfand -f
```

## Configuration

All values are read from environment variables with built-in defaults. Override
them by uncommenting the matching `Environment=` lines in the service unit
(`/etc/systemd/system/tpnsfand.service`), then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart tpnsfand
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `TPNSFAND_TEMP_FAN_ON` | 65 | °C at/above which the fan turns on |
| `TPNSFAND_TEMP_FAN_OFF` | 55 | °C below which the fan turns off |
| `TPNSFAND_TEMP_CTRL_EC` | 75 | °C at/above which control is handed to the EC |
| `TPNSFAND_TEMP_CTRL_HOST` | 70 | °C below which control is taken back from the EC |
| `TPNSFAND_RPM_LOW` | 2000 | target RPM at `TEMP_FAN_ON` (ramp start) |
| `TPNSFAND_RPM_HIGH` | 4165 | target RPM at `TEMP_CTRL_EC` (ramp end) |
| `TPNSFAND_INTERVAL` | 0.5 | poll interval in seconds (also the watchdog) |

Hardware-level values are also overridable (`TPNSFAND_EC_IO`, `TPNSFAND_REG_*`,
`TPNSFAND_CTRL_*`, `TPNSFAND_SPEED_*`) for adapting to a different model. Change
these only if you know your EC layout differs. **No validation is performed on
any value.**

## Behavior / Expectations

- Below `TEMP_FAN_ON` the fan is off; between the thresholds it ramps; above
  `TEMP_CTRL_EC` the EC takes over and runs its own curve. Under sustained heavy
  load the fan *will* spin — no setting keeps a hot CPU silent.
- **At high ambient temperatures** the fanless idle plateau can rise above
  `TEMP_FAN_ON`, producing a periodic on/off cycle over several minutes. This is
  physics, not a bug; it is still far quieter than the EC's constant idle fan.
  Raising `TEMP_FAN_ON` (if your machine stays cool enough) or reducing heat
  (e.g. capping turbo) mitigates it.
- Stopping the service or uninstalling returns fan control to the EC.

## Compatibility

Models below are the ones the kernel flags as non-standard (`TPACPI_FAN_NS`).
`dmidecode -s bios-version` prints the full BIOS version string (e.g.
`R1FET64W (1.38)`); its leading three characters are the `LNV3` code (here
`R1F`), which is what the kernel matches your machine against.

| Model | LNV3 | Support |
| --- | --- | --- |
| ThinkPad L13 Yoga Gen 2 | R1F | ✅ |
| ThinkPad L13 Yoga Gen 1 | R15 | ❓ |
| ThinkPad X13 Yoga Gen 2 | N2U | ❓ |
| ThinkPad X13 Yoga Gen 1 | N2L | ✅ |
| ThinkPad L390 | R10 | ❓ |
| ThinkPad L380 | R0R | ❓ |
| ThinkPad 11e Gen 5 GL | R0T | ❓ |
| ThinkPad 11e Gen 5 GL-R | R1D | ❓ |
| ThinkPad 11e Gen 5 KL-Y | R0V | ❓ |

Legend:

- ✅ **verified** — fan control tested and working.
- ❓ **no report yet** — suspected compatible (in the kernel NS list), but no
  community report submitted.
- ❌ **incompatible** — confirmed not working.

### Contribute a report

Help confirm your model. The report tool is **read-only** (it never writes EC
registers); it records identifying info plus how your EC drives the fan through
a short idle / load / idle cycle.

The test only yields useful data with the CPU unthrottled, so set the
**performance** platform profile first — the tool aborts on any other profile
(skip if your machine has no `platform_profile`):

```bash
echo performance | sudo tee /sys/firmware/acpi/platform_profile
```

Then:

```bash
git clone https://github.com/h4fnp/tpnsfand
cd tpnsfand
sudo modprobe ec_sys           # if not already loaded
sudo systemctl stop tpnsfand   # only if installed
sudo ./tools/tpnsfand-report   # requires stress-ng
```

Then submit the generated file one of two ways:

- open a pull request adding it under `reports/`, or
- post it in the [compatibility reports discussion](https://github.com/h4fnp/tpnsfand/discussions/1).

## Uninstall

```bash
sudo make uninstall
```

This stops the service (which returns control to the EC) and removes the files.

## Troubleshooting

- **`ec_sys.write_support` not `Y`** — the kernel command line did not take
  effect, or Secure Boot/lockdown is active. Recheck both and reboot.
- **Service crash-loops** — almost always the above: the daemon exits when it
  cannot write the EC. Fix the prerequisites first.
- **Fan stuck off/on after a hard kill** — `tpnsfand` returns control to the EC
  on normal stop, but not if it is `SIGKILL`ed. Restart the service, or set the
  control byte back to EC mode manually:

  ```bash
  printf '\x04' | sudo dd of=/sys/kernel/debug/ec/ec0/io bs=1 seek=147 count=1 conv=notrunc status=none
  ```

## Roadmap

The current approach requires `ec_sys.write_support=1` **and Secure Boot
disabled**, because kernel lockdown blocks EC writes through the `ec_sys`
debugfs interface. Two longer-term goals aim to remove that constraint so the
machine can run with Secure Boot enabled again:

- **Upstream `thinkpad_acpi` write support.** The driver already *reads* the
  non-standard fan registers; adding a *write*/control path upstream would let
  the in-tree (signed) driver drive the fan through a standard `pwm` interface —
  no `ec_sys`, no lockdown bypass, Secure Boot compatible.
- **A bundled DKMS module (interim).** Ship a small out-of-tree kernel module
  (built and installed via DKMS, signed with your own MOK key) that performs the
  EC writes in kernel space and exposes a control interface for `tpnsfand`. This
  keeps Secure Boot enabled without waiting for upstream, at the cost of a
  one-time MOK enrollment.

## License

GPL-2.0-only. See [LICENSE](LICENSE). Distributed without warranty.

## Background & References

The problem in the wild (user reports of the constant/uncontrollable fan):

- Lenovo Forums — *L13 Yoga gen 2 cannot control fan and sensors bad reading*
  (Ubuntu): <https://forums.lenovo.com/t5/Ubuntu/L13-Yoga-gen-2-cannot-control-fan-and-sensors-bad-reading/m-p/5251278>
- iFixit — *Why is the fan running constantly?* (L13 Yoga Gen 2):
  <https://www.ifixit.com/Answers/View/895532>
- Lenovo Forums — *ThinkPad L13 Yoga Gen 2 loud fan and heat*:
  <https://forums.lenovo.com/t5/ThinkPad-L-R-and-SL-series-Laptops/ThinkPad-L13-Yoga-Gen-2-loud-fan-and-heat/m-p/5069508>
- Arch Linux BBS — *Thinkpad Yoga and fan control* (related EC class):
  <https://bbs.archlinux.org/viewtopic.php?id=218564>
- A L13 Gen 2 user reporting thinkfan has no effect (blog comments):
  <https://blog.monosoul.dev/2021/10/17/how-to-control-thinkpad-p14s-fan-speed-in-linux/>
- `senior-sigan/lenovo-yoga-fan-control` — describes the same odd EC behavior on
  an older Yoga: <https://github.com/senior-sigan/lenovo-yoga-fan-control>

Upstream / kernel (the authoritative source for the NS layout):

- LKML — `thinkpad_acpi` fix for incorrect fan reporting on non-standard EC
  firmware (Dec 2023):
  <https://lkml.org/lkml/2023/12/6/947>
- LKML — adding more ThinkPads with non-standard register addresses (Feb 2024):
  <https://lkml.org/lkml/2024/2/29/2>
- The `ibm-acpi-devel` mailing list, where the NS read support was developed.
