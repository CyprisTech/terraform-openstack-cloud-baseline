# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before `v1.0.0`, minor versions may contain breaking changes; each one comes with migration notes.

## [Unreleased]

## [0.1.0] - 2026-11-18

### Added

- First release of the module ([ADR-0001](docs/adr/0001-module-design.md)): the foundation of a landing zone's projects, laid with the `admin` role.
  - Identity and projects: projects and their quotas (compute, network, block storage; only those given are managed), users with three password modes, groups and memberships, role assignments to users or groups, roles adopted by name.
  - Compute and images: flavors public or restricted to projects; images with their visibility, properties and sharing, accepted on the project's behalf.
  - Networks: external and internal networks, provider segments, subnets and host routes, shared with every project or with listed projects.
  - Routing and placement: address scopes and subnet pools shared with projects, subnets taken from a pool; host aggregates and availability zones.
  - Security: a catalogue of security groups owned by the administrator, with only the rules given.
  - DNS: zones created for a project or kept by the administrator and shared.
  - Adoption of existing projects, users, groups, networks and images; a [takeover guide](docs/takeover.md) for objects created by hand.
  - Outputs in the shape of the `existing` input of terraform-openstack-tenant.
- A disposable DevStack [test bench](tests/devstack/README.md), rebuilt from the repository, with a scenario per domain ([results](docs/testing.md)).
- Example [landing-zone-foundation](examples/landing-zone-foundation/README.md).

[Unreleased]: https://github.com/CyprisTech/terraform-openstack-cloud-baseline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CyprisTech/terraform-openstack-cloud-baseline/releases/tag/v0.1.0
