# SPDX-License-Identifier: GPL-2.0-only
# tpnsfand - install / uninstall
SBIN = /usr/local/sbin
UNIT = /etc/systemd/system

.PHONY: install uninstall check-root

check-root:
	@[ "$$(id -u)" = 0 ] || { echo "run as root: sudo make $(MAKECMDGOALS)"; exit 1; }

install: check-root
	install -m 755 src/tpnsfand $(SBIN)/tpnsfand
	install -m 644 src/tpnsfand.service $(UNIT)/tpnsfand.service
	systemctl daemon-reload
	systemctl enable tpnsfand.service
	@case "$$(cat /sys/module/ec_sys/parameters/write_support 2>/dev/null)" in Y|1) systemctl start tpnsfand.service ;; *) echo "NOTE: ec_sys.write_support not active - service enabled for next boot; see README prerequisites, then reboot." ;; esac

uninstall: check-root
	-systemctl disable --now tpnsfand.service
	-rm -f $(SBIN)/tpnsfand $(UNIT)/tpnsfand.service
	systemctl daemon-reload
