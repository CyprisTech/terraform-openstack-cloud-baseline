#!/usr/bin/env bash
# Bench checks of the takeover (docs/takeover.md). Run on the bench host, from a copy of the
# repository, after install.sh. Creates objects with the CLI as an operator would, then:
#   - the plan imports every object and creates or destroys nothing;
#   - apply, then an empty plan;
#   - destroy removes everything (the objects are the module's now).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/scenarios/takeover"
export OS_CLOUD=devstack-admin
failures=0
check() { if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }

cleanup() {
  set +e
  (cd "$dir" && [ -f ids.auto.tfvars.json ] && tofu destroy -auto-approve -input=false >/dev/null 2>&1)
  openstack zone delete --all-projects legacy.bench.example.org. >/dev/null 2>&1
  openstack security group delete bench-legacy-ssh >/dev/null 2>&1
  openstack network delete bench-legacy-net bench-legacy-ext >/dev/null 2>&1
  openstack flavor delete bench-legacy >/dev/null 2>&1
  openstack group delete bench-team >/dev/null 2>&1
  openstack user delete bench-erin >/dev/null 2>&1
  openstack project delete bench-legacy-web >/dev/null 2>&1
  rm -f "$dir/ids.auto.tfvars.json" "$dir"/terraform.tfstate*
  set -e
}
cleanup

# By hand, as an operator would.
project=$(openstack project create bench-legacy-web -f value -c id)
openstack quota set --cores 10 bench-legacy-web
user=$(openstack user create --password "$(openssl rand -hex 12)" bench-erin -f value -c id)
group=$(openstack group create bench-team -f value -c id)
openstack group add user bench-team bench-erin
openstack role add --group bench-team --project bench-legacy-web member
role=$(openstack role show member -f value -c id)
flavor=$(openstack flavor create --vcpus 1 --ram 512 --disk 1 bench-legacy -f value -c id)
network=$(openstack network create --provider-network-type geneve bench-legacy-net -f value -c id)
subnet=$(openstack subnet create --network bench-legacy-net --subnet-range 10.63.0.0/24 bench-legacy-net-main -f value -c id)
external_network=$(openstack network create --external --provider-network-type flat --provider-physical-network routed bench-legacy-ext -f value -c id)
external_subnet=$(openstack subnet create --network bench-legacy-ext --subnet-range 100.64.0.0/24 --gateway 100.64.0.1 --no-dhcp bench-legacy-ext-main -f value -c id)
# The policy Neutron created for every project ("*") when the network was made external.
external_rbac=$(openstack network rbac list --long -f json | jq -r --arg n "$external_network" '.[] | select(.["Object ID"] == $n and .Action == "access_as_external") | .ID')
network_rbac=$(openstack network rbac create --type network --action access_as_shared --target-project bench-legacy-web bench-legacy-net -f value -c id)
security_group=$(openstack security group create bench-legacy-ssh -f value -c id)
security_group_rule=$(openstack security group rule create --ingress --protocol tcp --dst-port 22 --remote-ip 192.0.2.0/24 bench-legacy-ssh -f value -c id)
security_group_rbac=$(openstack network rbac create --type security_group --action access_as_shared --target-project bench-legacy-web "$security_group" -f value -c id)
zone=$(openstack zone create --sudo-project-id "$project" --email dns@example.org legacy.bench.example.org. -f value -c id)
jq -n --arg project "$project" --arg user "$user" --arg group "$group" --arg role "$role" --arg flavor "$flavor" \
  --arg network "$network" --arg subnet "$subnet" --arg network_rbac "$network_rbac" \
  --arg external_network "$external_network" --arg external_subnet "$external_subnet" --arg external_rbac "$external_rbac" \
  --arg security_group "$security_group" --arg security_group_rule "$security_group_rule" \
  --arg security_group_rbac "$security_group_rbac" --arg zone "$zone" '{ids: $ARGS.named}' >"$dir/ids.auto.tfvars.json"

cd "$dir"
tofu init -input=false >/dev/null
tofu plan -input=false -no-color > /tmp/takeover-plan.txt
summary=$(grep -E '^Plan:' /tmp/takeover-plan.txt || echo "Plan: none")
echo "     $summary"
grep -E '# module.* (will be|must be)' /tmp/takeover-plan.txt | grep -v 'will be imported' | sed 's/^/     /' || true
check "plan imports and creates or destroys nothing" "$(grep -qE ' 0 to add,.* 0 to destroy' <<<"$summary" && echo ok)"
tofu apply -auto-approve -input=false >/dev/null
set +e; tofu plan -input=false -detailed-exitcode >/dev/null; rc=$?; set -e
check "empty plan after apply" "$([ "$rc" = 0 ] && echo ok)"
tofu destroy -auto-approve -input=false >/dev/null
check "destroy: project gone" "$(openstack project show bench-legacy-web >/dev/null 2>&1 || echo ok)"
check "destroy: network gone" "$(openstack network show bench-legacy-net >/dev/null 2>&1 || echo ok)"
rm -f ids.auto.tfvars.json
cleanup

echo "takeover: $failures failure(s)"
[ "$failures" -eq 0 ]
