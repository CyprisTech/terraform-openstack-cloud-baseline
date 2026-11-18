#!/usr/bin/env bash
# Bench checks of the catalogue of shared security groups (spec: first releases, tests of v0.1).
# Run on the bench host, from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan;
#   - a group shared with every project is attached by both projects;
#   - a group shared with one project is attached by it, not by the other;
#   - a project cannot add a rule to a shared group;
#   - a group has only the rules given (Neutron's default egress rules removed);
#   - destroy, nothing left.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/security"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
auth_url=$(openstack endpoint list --service identity --interface public -f value -c URL)
as_user() {  # as_user <user> <project> <openstack arguments...>
  local user=$1 project=$2; shift 2
  env -u OS_CLOUD OS_AUTH_URL="$auth_url" OS_IDENTITY_API_VERSION=3 OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    OS_USERNAME="$user" OS_PASSWORD="$(jq -r ".\"$user\"" <<<"$passwords")" OS_PROJECT_NAME="$project" openstack "$@"
}
ports_cleanup() {
  set +e
  for p in bench-p-alice bench-p-carol bench-p-carol-mon; do
    as_user bench-alice bench-web port delete "$p" >/dev/null 2>&1
    as_user bench-carol bench-ops port delete "$p" >/dev/null 2>&1
  done
  set -e
}

cd "$dir"
tofu init -input=false >/dev/null
if tofu output -json passwords >/dev/null 2>&1; then passwords=$(tofu output -json passwords); ports_cleanup; fi
tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode -no-color > /tmp/security-plan.txt; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
[ "$rc" = 0 ] || grep -E '^\s+[~+-] |# ' /tmp/security-plan.txt | head -12
passwords=$(tofu output -json passwords)
ssh_id=$(openstack security group show bench-ssh -f value -c id)
mon_id=$(openstack security group show bench-mon -f value -c id)

check "bench-alice attaches bench-ssh and bench-mon" "$(as_user bench-alice bench-web port create --network bench-sgnet --security-group "$ssh_id" --security-group "$mon_id" bench-p-alice >/dev/null 2>&1 && echo ok)"
check "bench-carol attaches bench-ssh" "$(as_user bench-carol bench-ops port create --network bench-sgnet --security-group "$ssh_id" bench-p-carol >/dev/null 2>&1 && echo ok)"
check "bench-carol cannot attach bench-mon" "$(as_user bench-carol bench-ops port create --network bench-sgnet --security-group "$mon_id" bench-p-carol-mon >/dev/null 2>&1 || echo ok)"
check "bench-carol cannot add a rule to bench-ssh" "$(as_user bench-carol bench-ops security group rule create --protocol tcp --dst-port 23 "$ssh_id" >/dev/null 2>&1 || echo ok)"
rules=$(openstack security group rule list "$mon_id" -f value | wc -l)
check "bench-mon has the 2 rules given ($rules)" "$([ "$rules" = 2 ] && echo ok)"

ports_cleanup
tofu destroy -auto-approve -input=false >/dev/null
left=$(openstack security group list --all-projects -f value -c Name | grep -c '^bench-' || true)
check "destroy: nothing left ($left)" "$([ "$left" = 0 ] && echo ok)"

echo "security: $failures failure(s)"
[ "$failures" -eq 0 ]
