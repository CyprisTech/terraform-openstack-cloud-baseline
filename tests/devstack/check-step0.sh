#!/usr/bin/env bash
# Exit criterion of step 0 of the bench (spec: docs/specs/devstack-test-bench.md), run on the
# bench host after install.sh, and again after a reboot of the host. Checks:
#   - the planes and their OVN mapping are up (they come back at boot);
#   - a member user's instance, on networks created by hand, reaches the four planes, resolves
#     names and reaches a package mirror;
#   - the instance is reachable from ns-internet through a floating IP;
#   - a volume is created and attached; a DNS zone and record become active.
# Everything it creates is deleted, before (a previous run may have stopped) and after.
set -euo pipefail

cd /opt/stack/devstack
PLANES="internet:203.0.113 intranet:192.0.2 publication:198.51.100 routed:100.64.0"
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }

as() {
  set +u
  # shellcheck disable=SC1091
  source openrc "$1" "$1" >/dev/null
  set -u
}

cleanup() {
  set +e
  as demo
  openstack server remove volume s0-vm s0-vol 2>/dev/null
  openstack server delete --wait s0-vm 2>/dev/null
  openstack volume delete s0-vol 2>/dev/null
  openstack floating ip list -f value -c ID --tags s0 2>/dev/null | xargs -r openstack floating ip delete
  openstack zone delete s0.example.org. >/dev/null 2>&1
  for p in $PLANES; do
    plane=${p%%:*}
    openstack router remove port "s0-$plane" "s0-$plane-port" 2>/dev/null
    openstack router remove subnet "s0-$plane" s0-net 2>/dev/null
    openstack router delete "s0-$plane" 2>/dev/null
  done
  openstack network delete s0-net 2>/dev/null
  openstack security group delete s0 2>/dev/null
  as admin
  for p in $PLANES; do openstack network delete "s0-${p%%:*}" 2>/dev/null; done
  set -e
}
cleanup
trap cleanup EXIT

# Planes and OVN mapping, as after a boot.
check "planes up" "$(sudo devstack-planes status | grep -cw up | grep -qx 4 && echo ok)"
mappings=$(sudo ovs-vsctl get open . external-ids:ovn-bridge-mappings)
check "OVN bridge mappings ($mappings)" "$(grep -q 'routed:br-routed' <<<"$mappings" && echo ok)"

# The operator's side: one external network per plane.
as admin
for p in $PLANES; do
  plane=${p%%:*} prefix=${p#*:}
  openstack network create --external --provider-network-type flat --provider-physical-network "$plane" "s0-$plane" >/dev/null
  openstack subnet create --network "s0-$plane" --subnet-range "$prefix.0/24" --gateway "$prefix.1" \
    --allocation-pool "start=$prefix.100,end=$prefix.199" --no-dhcp "s0-$plane" >/dev/null
done

# The tenant's side, as the member user: the default route through the internet plane, a
# router and a host route to each other plane.
as demo
openstack network create s0-net >/dev/null
openstack subnet create --network s0-net --subnet-range 10.50.0.0/24 --dns-nameserver 9.9.9.9 s0-net >/dev/null
openstack router create --external-gateway s0-internet s0-internet >/dev/null
openstack router add subnet s0-internet s0-net
host=250
for p in $PLANES; do
  plane=${p%%:*} prefix=${p#*:}
  [ "$plane" = internet ] && continue
  openstack router create --external-gateway "s0-$plane" "s0-$plane" >/dev/null
  openstack port create --network s0-net --fixed-ip "subnet=s0-net,ip-address=10.50.0.$host" "s0-$plane-port" >/dev/null
  openstack router add port "s0-$plane" "s0-$plane-port"
  openstack subnet set --host-route "destination=$prefix.0/24,gateway=10.50.0.$host" s0-net
  host=$((host + 1))
done
openstack security group create s0 >/dev/null
openstack security group rule create --protocol icmp s0 >/dev/null

cat >/tmp/s0-userdata <<'UD'
#!/bin/sh
sleep 10
for t in 203.0.113.2 192.0.2.2 198.51.100.2 100.64.0.2; do
  ping -c 3 -W 2 $t >/dev/null && echo "S0 ping $t ok" || echo "S0 ping $t fail"
done
nslookup archive.ubuntu.com >/dev/null 2>&1 && echo "S0 dns ok" || echo "S0 dns fail"
wget -q -O /dev/null http://archive.ubuntu.com/ubuntu/ && echo "S0 mirror ok" || echo "S0 mirror fail"
UD
image=$(openstack image list -f value -c Name | grep -m1 cirros)
openstack server create --flavor m1.tiny --image "$image" --network s0-net --security-group s0 \
  --user-data /tmp/s0-userdata --wait s0-vm >/dev/null

log=""
for _ in $(seq 1 40); do
  log=$(openstack console log show s0-vm)
  [ "$(grep -c '^S0 ' <<<"$log")" -ge 6 ] && break
  sleep 10
done
for line in "ping 203.0.113.2" "ping 192.0.2.2" "ping 198.51.100.2" "ping 100.64.0.2" "dns" "mirror"; do
  check "instance: $line" "$(grep -q "^S0 $line ok" <<<"$log" && echo ok)"
done

# Inbound through a floating IP on the internet plane.
fip=$(openstack floating ip create --tag s0 s0-internet -f value -c floating_ip_address)
openstack server add floating ip s0-vm "$fip"
ok=""
for _ in $(seq 1 12); do
  if sudo ip netns exec ns-internet ping -c 1 -W 2 "$fip" >/dev/null; then ok=ok; break; fi
  sleep 5
done
check "floating IP $fip from ns-internet" "$ok"

# Block storage: a volume created and attached.
openstack volume create --size 1 s0-vol >/dev/null
for _ in $(seq 1 24); do [ "$(openstack volume show s0-vol -f value -c status)" = available ] && break; sleep 5; done
openstack server add volume s0-vm s0-vol >/dev/null
status=""
for _ in $(seq 1 24); do status=$(openstack volume show s0-vol -f value -c status); [ "$status" = in-use ] && break; sleep 5; done
check "volume attached ($status)" "$([ "$status" = in-use ] && echo ok)"

# DNS: a zone and a record become active.
openstack zone create --email ops@example.org s0.example.org. >/dev/null
openstack recordset create --type A --record 192.0.2.10 s0.example.org. www >/dev/null
status=""
for _ in $(seq 1 24); do status=$(openstack recordset show s0.example.org. www.s0.example.org. -f value -c status); [ "$status" = ACTIVE ] && break; sleep 5; done
check "DNS record ($status)" "$([ "$status" = ACTIVE ] && echo ok)"

echo "step 0: $failures failure(s)"
[ "$failures" -eq 0 ]
