#!/usr/bin/env bash
# Bench checks of the external and shared networks (spec: first releases, tests of v0.1). Run on
# the bench host, from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan;
#   - an external network shared with every project is a router gateway for both projects;
#   - an external network shared with one project is a gateway for that project only;
#   - an internal network shared with one project takes its ports, and is hidden from the other;
#   - the host route reaches the subnet;
#   - destroy, nothing left.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/networks"
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
  as_user bench-alice bench-web router delete bench-r-public bench-r-intranet >/dev/null 2>&1
  as_user bench-carol bench-ops router delete bench-r-public bench-r-intranet >/dev/null 2>&1
  as_user bench-alice bench-web port delete bench-p-transit >/dev/null 2>&1
  set -e
}

# A network created beforehand, adopted and shared by the module.
openstack network show bench-legacy-shared >/dev/null 2>&1 || openstack network create bench-legacy-shared >/dev/null

cd "$dir"
tofu init -input=false >/dev/null
if tofu output -json passwords >/dev/null 2>&1; then passwords=$(tofu output -json passwords); users_cleanup; fi
tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode -no-color > /tmp/networks-plan.txt; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
[ "$rc" = 0 ] || grep -E '^\s+[~+-] |# ' /tmp/networks-plan.txt | head -12
passwords=$(tofu output -json passwords)

check "bench-alice: router gateway on bench-public" "$(as_user bench-alice bench-web router create --external-gateway bench-public bench-r-public >/dev/null 2>&1 && echo ok)"
check "bench-carol: router gateway on bench-public" "$(as_user bench-carol bench-ops router create --external-gateway bench-public bench-r-public >/dev/null 2>&1 && echo ok)"
check "bench-alice: router gateway on bench-intranet (shared with bench-web)" "$(as_user bench-alice bench-web router create --external-gateway bench-intranet bench-r-intranet >/dev/null 2>&1 && echo ok)"
check "bench-carol: no gateway on bench-intranet" "$(as_user bench-carol bench-ops router create --external-gateway bench-intranet bench-r-intranet >/dev/null 2>&1 || echo ok)"
check "bench-carol: bench-intranet not listed" "$(as_user bench-carol bench-ops network list -f value -c Name | grep -qx bench-intranet || echo ok)"
check "bench-alice: port on bench-transit" "$(as_user bench-alice bench-web port create --network bench-transit bench-p-transit >/dev/null 2>&1 && echo ok)"
check "bench-carol: bench-transit not listed" "$(as_user bench-carol bench-ops network list -f value -c Name | grep -qx bench-transit || echo ok)"
routes=$(openstack subnet show bench-transit-main -f json | jq -r '.host_routes | tostring')
check "host route on bench-transit ($routes)" "$(grep -q '10.70.0.0/16' <<<"$routes" && echo ok)"
check "bench-alice sees the adopted bench-legacy-shared" "$(as_user bench-alice bench-web network list -f value -c Name | grep -qx bench-legacy-shared && echo ok)"
check "bench-carol does not see bench-legacy-shared" "$(as_user bench-carol bench-ops network list -f value -c Name | grep -qx bench-legacy-shared || echo ok)"
mtu=$(openstack network show bench-transit -f value -c mtu)
check "MTU of bench-transit ($mtu)" "$([ "$mtu" = 1400 ] && echo ok)"

users_cleanup
tofu destroy -auto-approve -input=false >/dev/null
check "destroy: the adopted network is kept" "$(openstack network show bench-legacy-shared >/dev/null 2>&1 && echo ok)"
openstack network delete bench-legacy-shared >/dev/null
left=$(openstack network list -f value -c Name | grep -c '^bench-' || true)
check "destroy: nothing left ($left)" "$([ "$left" = 0 ] && echo ok)"

echo "networks: $failures failure(s)"
[ "$failures" -eq 0 ]
