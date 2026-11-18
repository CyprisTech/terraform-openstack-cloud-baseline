#!/usr/bin/env bash
# Bench checks of the flavors and images (spec: first releases, tests of v0.1). Run on the bench
# host, from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan (Glance adds properties of its own);
#   - a restricted flavor is visible in its project only;
#   - a shared image accepted on the project's behalf by an administrator is visible to a member;
#   - a shared image not accepted is not listed for the member;
#   - destroy, nothing left.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/compute"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
auth_url=$(openstack endpoint list --service identity --interface public -f value -c URL)
as_user() {  # as_user <user> <project> <openstack arguments...>
  local user=$1 project=$2; shift 2
  env -u OS_CLOUD OS_AUTH_URL="$auth_url" OS_IDENTITY_API_VERSION=3 OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    OS_USERNAME="$user" OS_PASSWORD="$(jq -r ".\"$user\"" <<<"$passwords")" OS_PROJECT_NAME="$project" openstack "$@"
}

# An image created beforehand (shared visibility), adopted and shared by the module.
if ! openstack image show bench-golden >/dev/null 2>&1; then
  curl -fsSL -o /tmp/bench-golden.img https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
  openstack image create --disk-format qcow2 --container-format bare --shared --file /tmp/bench-golden.img bench-golden >/dev/null
  rm -f /tmp/bench-golden.img
fi

cd "$dir"
tofu init -input=false >/dev/null
tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode -no-color > /tmp/compute-plan.txt; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
[ "$rc" = 0 ] || grep -E '^\s+[~+-] ' /tmp/compute-plan.txt | head -10

passwords=$(tofu output -json passwords)
check "bench-alice (bench-web) sees bench-restricted" "$(as_user bench-alice bench-web flavor list -f value -c Name | grep -qx bench-restricted && echo ok)"
check "bench-carol (bench-ops) does not see bench-restricted" "$(as_user bench-carol bench-ops flavor list -f value -c Name | grep -qx bench-restricted || echo ok)"
check "bench-alice sees bench-shared (accepted by the module)" "$(as_user bench-alice bench-web image list -f value -c Name | grep -qx bench-shared && echo ok)"
check "bench-carol does not list bench-unaccepted (pending)" "$(as_user bench-carol bench-ops image list -f value -c Name | grep -qx bench-unaccepted || echo ok)"
check "bench-alice sees the adopted bench-golden (accepted)" "$(as_user bench-alice bench-web image list -f value -c Name | grep -qx bench-golden && echo ok)"
check "bench-carol does not see bench-golden" "$(as_user bench-carol bench-ops image list -f value -c Name | grep -qx bench-golden || echo ok)"
check "bench-carol sees bench-public" "$(as_user bench-carol bench-ops image list -f value -c Name | grep -qx bench-public && echo ok)"

tofu destroy -auto-approve -input=false >/dev/null
check "destroy: the adopted image is kept" "$(openstack image show bench-golden >/dev/null 2>&1 && echo ok)"
openstack image delete bench-golden >/dev/null
left=$(openstack image list -f value -c Name | grep -c '^bench-' || true; openstack flavor list --all -f value -c Name | grep -c '^bench-' || true)
check "destroy: nothing left ($(echo "$left" | tr '\n' ' '))" "$([ "$(echo "$left" | paste -sd+ | bc)" = 0 ] && echo ok)"

echo "compute: $failures failure(s)"
[ "$failures" -eq 0 ]
