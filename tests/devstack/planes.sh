#!/usr/bin/env bash
# Simulated operator planes of the DevStack test bench (spec: docs/specs/devstack-test-bench.md).
#
# One Open vSwitch bridge per plane, mapped to a physical network in local.conf, and a network
# namespace behind each bridge playing the outside of the plane: the operator's side of the plane
# (its first address) and a client. The internet namespace also routes to the host, which
# translates to its uplink, so that instances reach package mirrors.
#
# Usage: sudo planes.sh up | down | status       Idempotent; nothing leaves the host but egress.
set -euo pipefail

# Namespaces and bridges need root.
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

# plane  bridge          namespace      range of the plane (documentation ranges)
PLANES=(
  "internet    br-internet    ns-internet  203.0.113.0/24"
  "intranet    br-intranet    ns-onprem    192.0.2.0/24"
  "publication br-publication ns-consumer  198.51.100.0/24"
  "routed      br-routed      ns-operator  100.64.0.0/24"
)
# Link between the host and ns-internet, for egress.
UPLINK_HOST=10.255.255.1/30
UPLINK_NS=10.255.255.2/30

first_ip() { local net=${1%/*} len=${1#*/}; echo "${net%.*}.$(( ${net##*.} + 1 ))/$len"; }
second_ip() { local net=${1%/*} len=${1#*/}; echo "${net%.*}.$(( ${net##*.} + 2 ))/$len"; }

up() {
  for p in "${PLANES[@]}"; do
    read -r plane br ns cidr <<<"$p"
    ovs-vsctl --may-exist add-br "$br"
    ip link set "$br" up
    ip netns list | grep -qw "$ns" || ip netns add "$ns"
    ip netns exec "$ns" ip link set lo up
    if ! ip link show "v-$plane" >/dev/null 2>&1; then
      ip link add "v-$plane" type veth peer name eth0 netns "$ns"
      ovs-vsctl --may-exist add-port "$br" "v-$plane"
      ip link set "v-$plane" up
      ip netns exec "$ns" ip addr add "$(first_ip "$cidr")" dev eth0   # the operator's side
      ip netns exec "$ns" ip addr add "$(second_ip "$cidr")" dev eth0  # a client
      ip netns exec "$ns" ip link set eth0 up
    fi
  done

  # OVN maps each physical network to its bridge. DevStack sets this mapping only when it
  # creates the public network itself, which the bench disables.
  local mappings=""
  for p in "${PLANES[@]}"; do
    read -r plane br _ _ <<<"$p"
    mappings="${mappings:+$mappings,}$plane:$br"
  done
  ovs-vsctl set open . external-ids:ovn-bridge-mappings="$mappings"

  # Egress: ns-internet routes to the host, the host translates to its uplink.
  if ! ip link show v-uplink >/dev/null 2>&1; then
    ip link add v-uplink type veth peer name uplink netns ns-internet
    ip addr add "$UPLINK_HOST" dev v-uplink
    ip link set v-uplink up
    ip netns exec ns-internet ip addr add "$UPLINK_NS" dev uplink
    ip netns exec ns-internet ip link set uplink up
    ip netns exec ns-internet ip route add default via "${UPLINK_HOST%/*}"
    ip netns exec ns-internet sysctl -qw net.ipv4.ip_forward=1
  fi
  sysctl -qw net.ipv4.ip_forward=1
  local internet_cidr; internet_cidr=$(awk '{print $4}' <<<"${PLANES[0]}")
  ip route replace "$internet_cidr" via "${UPLINK_NS%/*}"
  local uplink_dev; uplink_dev=$(ip route show default | awk '{print $5; exit}')
  iptables -t nat -C POSTROUTING -s "$internet_cidr" -o "$uplink_dev" -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -s "$internet_cidr" -o "$uplink_dev" -j MASQUERADE
  iptables -C FORWARD -i v-uplink -o "$uplink_dev" -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -i v-uplink -o "$uplink_dev" -j ACCEPT
  iptables -C FORWARD -i "$uplink_dev" -o v-uplink -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -i "$uplink_dev" -o v-uplink -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

down() {
  local internet_cidr uplink_dev
  internet_cidr=$(awk '{print $4}' <<<"${PLANES[0]}")
  uplink_dev=$(ip route show default | awk '{print $5; exit}')
  iptables -t nat -D POSTROUTING -s "$internet_cidr" -o "$uplink_dev" -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -i v-uplink -o "$uplink_dev" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$uplink_dev" -o v-uplink -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  ip route del "$internet_cidr" 2>/dev/null || true
  ip link del v-uplink 2>/dev/null || true
  for p in "${PLANES[@]}"; do
    read -r plane br ns _ <<<"$p"
    ovs-vsctl --if-exists del-port "$br" "v-$plane"
    ip link del "v-$plane" 2>/dev/null || true
    ip netns del "$ns" 2>/dev/null || true
  done
}

status() {
  for p in "${PLANES[@]}"; do
    read -r plane br ns cidr <<<"$p"
    printf '%-12s %-15s %-12s %-16s ' "$plane" "$br" "$ns" "$cidr"
    if ip netns exec "$ns" ip -brief addr show eth0 2>/dev/null | grep -q UP; then echo up; else echo down; fi
  done
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
