#!/usr/bin/env bash
# Bench checks of the DNS zones (spec: first releases, tests of v0.1). Run on the bench host,
# from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan (the stack still reads the zone owned by the project);
#   - a zone created for a project is owned by it: its member writes a record, another cannot;
#   - a shared zone: members of the projects it is shared with write records, another cannot;
#   - destroy, nothing left.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/dns"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
auth_url=$(openstack endpoint list --service identity --interface public -f value -c URL)
as_user() {  # as_user <user> <project> <openstack arguments...>
  local user=$1 project=$2; shift 2
  env -u OS_CLOUD OS_AUTH_URL="$auth_url" OS_IDENTITY_API_VERSION=3 OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    OS_USERNAME="$user" OS_PASSWORD="$(jq -r ".\"$user\"" <<<"$passwords")" OS_PROJECT_NAME="$project" openstack "$@"
}
records_cleanup() {
  set +e
  as_user bench-alice bench-web recordset delete web.bench.example.org. www.web.bench.example.org. >/dev/null 2>&1
  as_user bench-alice bench-web recordset delete svc.bench.example.org. alice.svc.bench.example.org. >/dev/null 2>&1
  as_user bench-carol bench-ops recordset delete svc.bench.example.org. carol.svc.bench.example.org. >/dev/null 2>&1
  sleep 5
  set -e
}

cd "$dir"
tofu init -input=false >/dev/null
if tofu output -json passwords >/dev/null 2>&1; then passwords=$(tofu output -json passwords); records_cleanup; fi
tofu destroy -auto-approve -input=false >/dev/null 2>&1 || true
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode -no-color > /tmp/dns-plan.txt; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
[ "$rc" = 0 ] || grep -E '^\s+[~+-] |# ' /tmp/dns-plan.txt | head -12
passwords=$(tofu output -json passwords)

web_project=$(openstack project show bench-web -f value -c id)
owner=$(openstack zone show --all-projects web.bench.example.org. -f value -c project_id 2>/dev/null || true)
check "web.bench.example.org. owned by bench-web" "$([ "$owner" = "$web_project" ] && echo ok)"
check "bench-alice writes a record in her project's zone" "$(as_user bench-alice bench-web recordset create --type A --record 192.0.2.10 web.bench.example.org. www >/dev/null 2>&1 && echo ok)"
check "bench-carol cannot write in that zone" "$(as_user bench-carol bench-ops recordset create --type A --record 192.0.2.11 web.bench.example.org. intruder >/dev/null 2>&1 || echo ok)"
check "bench-alice writes in the shared zone" "$(as_user bench-alice bench-web recordset create --type A --record 192.0.2.20 svc.bench.example.org. alice >/dev/null 2>&1 && echo ok)"
check "bench-carol writes in the shared zone" "$(as_user bench-carol bench-ops recordset create --type A --record 192.0.2.21 svc.bench.example.org. carol >/dev/null 2>&1 && echo ok)"
check "bench-dave cannot write in the shared zone" "$(as_user bench-dave bench-other recordset create --type A --record 192.0.2.22 svc.bench.example.org. dave >/dev/null 2>&1 || echo ok)"

records_cleanup
tofu destroy -auto-approve -input=false >/dev/null
left=$(openstack zone list --all-projects -f value -c name | grep -c 'bench.example.org' || true)
check "destroy: nothing left ($left)" "$([ "$left" = 0 ] && echo ok)"

echo "dns: $failures failure(s)"
[ "$failures" -eq 0 ]
