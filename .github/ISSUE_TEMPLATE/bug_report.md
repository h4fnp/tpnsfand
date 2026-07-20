---
name: Bug report
about: Report a problem with tpnsfand
title: ''
labels: bug
assignees: ''

---

**Bug Description**
<!-- What went wrong: fan stuck on/off, service crash-loop, wrong temperatures, etc. -->


**Expected behavior**
<!-- What you expected to happen instead. -->


**Steps to Reproduce**
1. ...
2. ...
3. See error


**tpnsfand logs**
<!-- Paste the output of:
       journalctl -u tpnsfand -b --no-pager
     If the service is crash-looping, this is the most important field. -->
````

````

**Report-tool output**
<!-- Run the read-only report tool (README -> "Contribute a report"):
       echo performance | sudo tee /sys/firmware/acpi/platform_profile   (skip if no platform_profile)
       sudo modprobe ec_sys
       sudo systemctl stop tpnsfand        (only if installed)
       sudo ./tools/tpnsfand-report        (requires stress-ng)
     Then attach or paste the generated file here. It already records model,
     BIOS version, Secure Boot state, kernel lockdown, and EC write support. -->
````

````

**System info**
<!-- Fill in below if you did NOT run the report tool:
       Model + BIOS:      dmidecode -s bios-version
       Secure Boot:       mokutil --sb-state
       Kernel lockdown:   cat /sys/kernel/security/lockdown
       EC write support:  cat /sys/module/ec_sys/parameters/write_support
       Distro / kernel:   . /etc/os-release; echo "$PRETTY_NAME $(uname -r)" -->
- Model + BIOS:
- Secure Boot:
- Kernel lockdown:
- EC write support:
- Distro / kernel:
- tpnsfand version / commit:


**Additional context**
<!-- Anything else: custom TPNSFAND_* overrides, when it started, related
     hardware quirks, sensors output, etc. -->
