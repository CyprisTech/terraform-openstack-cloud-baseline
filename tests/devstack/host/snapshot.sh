#!/usr/bin/env bash
# Snapshot of the bench host, so that a session restarts from a built bench instead of running
# stack.sh again (spec: docs/specs/devstack-test-bench.md, design 5). The instance is stopped
# for a consistent disk, snapshotted as a private image, then started again. The previous
# snapshot of the same step is deleted once the new one is active.
#
# Usage: ./snapshot.sh <step>      e.g. ./snapshot.sh step0       (OS_CLOUD set to the hosting project)
set -euo pipefail

step=${1:?usage: $0 <step>}
server=devstack-bench
name="devstack-bench-$step-$(date -u +%Y%m%d%H%M)"

previous=$(openstack image list --private -f value -c ID -c Name | awk -v p="devstack-bench-$step-" 'index($2, p) == 1 {print $1}')

openstack server stop "$server"
until [ "$(openstack server show "$server" -f value -c status)" = SHUTOFF ]; do sleep 5; done
openstack server image create --wait --name "$name" "$server"
openstack server start "$server"

[ "$(openstack image show "$name" -f value -c status)" = active ]
for id in $previous; do openstack image delete "$id"; done
echo "$name"
