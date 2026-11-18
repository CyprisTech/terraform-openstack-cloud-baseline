#!/usr/bin/env bash
# Bench checks of the address scopes, subnet pools and aggregates (spec: first releases, tests of
# v0.1). Run on the bench host, from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan;
#   - a member of the project a pool is shared with takes a subnet from it; another project cannot;
#   - a range already allocated in the pool is refused;
#   - the aggregate forms an availability zone, and an instance is placed in it;
#   - destroy, nothing left, the host back in its former zone.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/routing"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
auth_url=$(openstack endpoint list --service identity --interface public -f value -c URL)
as_user() {  # as_user <user> <project> <openstack arguments...>
  local user=$1 project=$2; shift 2
  env -u OS_CLOUD OS_AUTH_URL="$auth_url" OS_IDENTITY_API_VERSION=3 OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    OS_USERNAME="$user" OS_PASSWORD="$(jq -r ".\"$user\"" <<<"$passwords")" OS_PROJECT_NAME="$project" openstack "$@"
}
users_cleanup() {
  set +e
  as_user bench-alice bench-web server delete --wait bench-vm-zone >/dev/null 2>&1
  as_user bench-alice bench-web network delete bench-alice-net bench-alice-net2 >/dev/null 2>&1
  as_user bench-carol bench-ops network delete bench-carol-net >/dev/null 2>&1
  set -e
}
host=$(openstack compute service list --service nova-compute -f value -c Host | head -1)
export TF_VAR_compute_host="$host"

cd "$dir"
tofu init -input=false >/dev/null
if tofu output -json passwords >/dev/null 2>&1; then passwords=$(tofu output -json passwords); users_cleanup; fi
tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
zone_before=$(openstack compute service list --service nova-compute -f value -c Zone | head -1)
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode -no-color > /tmp/routing-plan.txt; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
[ "$rc" = 0 ] || grep -E '^\s+[~+-] |# ' /tmp/routing-plan.txt | head -12
passwords=$(tofu output -json passwords)

pooled=$(openstack subnet show bench-pooled-main -f value -c cidr)
check "bench-pooled took its range from the pool ($pooled)" "$(grep -q '^10\.80\.' <<<"$pooled" && echo ok)"
as_user bench-alice bench-web network create bench-alice-net >/dev/null
check "bench-alice takes a subnet from bench-pool" "$(as_user bench-alice bench-web subnet create --network bench-alice-net --subnet-pool bench-pool bench-alice-sub >/dev/null 2>&1 && echo ok)"
as_user bench-alice bench-web network create bench-alice-net2 >/dev/null
check "a range already allocated in the pool is refused" "$(as_user bench-alice bench-web subnet create --network bench-alice-net2 --subnet-pool bench-pool --subnet-range "$pooled" bench-alice-dup >/dev/null 2>&1 || echo ok)"
as_user bench-carol bench-ops network create bench-carol-net >/dev/null
check "bench-carol cannot use bench-pool" "$(as_user bench-carol bench-ops subnet create --network bench-carol-net --subnet-pool bench-pool bench-carol-sub >/dev/null 2>&1 || echo ok)"

check "availability zone bench-zone listed" "$(openstack availability zone list --compute -f value -c 'Zone Name' | grep -qx bench-zone && echo ok)"
image=$(openstack image list -f value -c Name | grep -m1 cirros)
as_user bench-alice bench-web server create --flavor m1.tiny --image "$image" --network bench-alice-net \
  --availability-zone bench-zone --wait bench-vm-zone >/dev/null 2>/tmp/routing-server.err || sed 's/^/     /' /tmp/routing-server.err
az=$(as_user bench-alice bench-web server show bench-vm-zone -f value -c OS-EXT-AZ:availability_zone 2>/dev/null || true)
check "instance placed in bench-zone ($az)" "$([ "$az" = bench-zone ] && echo ok)"

users_cleanup
tofu destroy -auto-approve -input=false >/dev/null
left=$( (openstack subnet pool list -f value -c Name; openstack address scope list -f value -c Name; openstack aggregate list -f value -c Name) | grep -c '^bench-' || true)
check "destroy: nothing left ($left)" "$([ "$left" = 0 ] && echo ok)"
zone_after=$(openstack compute service list --service nova-compute -f value -c Zone | head -1)
check "host back in its zone ($zone_after)" "$([ "$zone_after" = "$zone_before" ] && echo ok)"

echo "routing: $failures failure(s)"
[ "$failures" -eq 0 ]
