#!/usr/bin/env bash
# Bench checks of the identity and projects domain (spec: first releases, tests of v0.1).
# Run on the bench host, from a copy of the repository, after install.sh. Checks:
#   - apply, then an empty plan;
#   - adopted objects (a project and a user created beforehand) receive roles and memberships;
#   - a created user logs in with its generated password, on its project only;
#   - a user gets a role through its group, on a created and an adopted project;
#   - quotas given are set, the others keep the cloud's defaults;
#   - destroy removes what the module created, and only that.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/identity"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
login() {  # login <user> <password> <project>: a token scoped to the project
  env -u OS_CLOUD OS_AUTH_URL="$auth_url" OS_IDENTITY_API_VERSION=3 OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    OS_USERNAME="$1" OS_PASSWORD="$2" OS_PROJECT_NAME="$3" openstack token issue -f value -c id >/dev/null 2>&1
}
auth_url=$(openstack endpoint list --service identity --interface public -f value -c URL)

cleanup() {
  set +e
  (cd "$dir" && tofu destroy -auto-approve -input=false >/dev/null 2>&1)
  openstack user delete bench-bob 2>/dev/null
  openstack project delete bench-legacy 2>/dev/null
  set -e
}
cleanup

# Objects owned elsewhere, adopted by the module.
bob_password=$(openssl rand -hex 12)
openstack project create bench-legacy >/dev/null
openstack user create --password "$bob_password" bench-bob >/dev/null

cd "$dir"
tofu init -input=false >/dev/null
tofu apply -auto-approve -input=false >/dev/null
check "apply" ok
set +e; tofu plan -input=false -detailed-exitcode >/dev/null; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"

alice_password=$(tofu output -json passwords | jq -r '."bench-alice"')
check "bench-alice logs in on bench-web" "$(login bench-alice "$alice_password" bench-web && echo ok)"
check "bench-alice has no role on admin" "$(login bench-alice "$alice_password" admin || echo ok)"
check "bench-bob (adopted) gets member on bench-shared through bench-ops" "$(login bench-bob "$bob_password" bench-shared && echo ok)"
check "bench-bob gets reader on bench-legacy (adopted) through bench-ops" "$(login bench-bob "$bob_password" bench-legacy && echo ok)"

cores=$(openstack quota show bench-web -f json | jq '.[] | select(.Resource == "cores") | .Limit')
subnets=$(openstack quota show bench-web -f json | jq '.[] | select(.Resource == "subnets") | .Limit')
default_subnets=$(openstack quota show --default -f json | jq '.[] | select(.Resource == "subnets") | .Limit')
check "quota cores = 8" "$([ "$cores" = 8 ] && echo ok)"
check "quota subnets left to the cloud ($subnets = default $default_subnets)" "$([ "$subnets" = "$default_subnets" ] && echo ok)"

tofu destroy -auto-approve -input=false >/dev/null
check "destroy: bench-web gone" "$(openstack project show bench-web >/dev/null 2>&1 || echo ok)"
check "destroy: adopted bench-legacy and bench-bob kept" "$(openstack project show bench-legacy >/dev/null 2>&1 && openstack user show bench-bob >/dev/null 2>&1 && echo ok)"
cleanup

echo "identity: $failures failure(s)"
[ "$failures" -eq 0 ]
