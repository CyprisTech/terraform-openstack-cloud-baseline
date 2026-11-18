#!/usr/bin/env bash
# Builds the DevStack test bench on the bench host, as the user stack (spec:
# docs/specs/devstack-test-bench.md): the simulated planes, then DevStack.
# Usage: ./install.sh        (from a copy of this repository on the bench host)
# After a failure of stack.sh (a download that timed out, for example), run it again: it
# resumes; if it fails the same way, rebuild the host instead of repairing it.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
branch=stable/2026.1
tofu_version=1.13.2
tofu_sha256=ac05d9952662c7db28dd57e93f0a68018837bfdf9342384ec0987977c16a9645

# The bench is never upgraded (spec, design 5): no automatic upgrades. They would update
# packages under DevStack, and restart Apache, hence Keystone, in the middle of a check.
sudo systemctl disable --now unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

# The tools of the checks: OpenTofu (pinned, checksum verified), jq, bc.
sudo apt-get install -y -qq jq bc >/dev/null
if [ "$(tofu version 2>/dev/null | head -1)" != "OpenTofu v$tofu_version" ]; then
  archive=$(mktemp)
  curl -fsSL -o "$archive" "https://github.com/opentofu/opentofu/releases/download/v$tofu_version/tofu_${tofu_version}_linux_amd64.tar.gz"
  echo "$tofu_sha256  $archive" | sha256sum -c --quiet
  sudo tar -xzf "$archive" -C /usr/local/bin tofu
  rm -f "$archive"
fi

# Nested virtualization: without /dev/kvm, instances run under plain QEMU (spec, design 1).
[ -e /dev/kvm ] || echo "warning: /dev/kvm missing, instances will be slow" >&2

# The planes, now and at every boot.
sudo install -m 0755 "$here/planes.sh" /usr/local/sbin/devstack-planes
sudo tee /etc/systemd/system/devstack-planes.service >/dev/null <<'UNIT'
[Unit]
Description=Simulated operator planes of the DevStack test bench
After=openvswitch-switch.service network-online.target
Wants=openvswitch-switch.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/devstack-planes up
ExecStop=/usr/local/sbin/devstack-planes down

[Install]
WantedBy=multi-user.target
UNIT

# DevStack, pinned to a stable branch.
sudo mkdir -p /opt/stack && sudo chown "$USER" /opt/stack
[ -d /opt/stack/devstack ] || git clone -b "$branch" https://opendev.org/openstack/devstack /opt/stack/devstack

# Secrets of the disposable cloud, kept on the bench only.
secrets=$HOME/.devstack-password
[ -f "$secrets" ] || (umask 077 && openssl rand -hex 16 >"$secrets")
host_ip=$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')
sed -e "s/@HOST_IP@/$host_ip/" -e "s/@PASSWORD@/$(cat "$secrets")/" \
  "$here/local.conf.tmpl" >/opt/stack/devstack/local.conf
chmod 600 /opt/stack/devstack/local.conf

# DevStack installs Open vSwitch: the planes come up after it.
cd /opt/stack/devstack
./stack.sh
sudo systemctl daemon-reload
sudo systemctl enable --now devstack-planes.service
/usr/local/sbin/devstack-planes status
