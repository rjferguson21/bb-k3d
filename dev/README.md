# BigBang Development Taskfiles

Task automation for [BigBang](https://repo1.dso.mil/big-bang/bigbang) development workflows. Provides tasks for creating k3d clusters, deploying BigBang, and running tests — locally or on an EC2 instance driven through a docker context.

## Requirements

- [go-task](https://taskfile.dev/)
- [helm](https://helm.sh/)
- [yq](https://github.com/mikefarah/yq)
- [k3d](https://k3d.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- AWS CLI (for remote development)

## Configuration

Set Registry1 credentials as environment variables:

```bash
export REGISTRY1_USERNAME=<username>
export REGISTRY1_PASSWORD=<password>
```

## Local development

Everything runs against your local docker daemon by default:

```bash
task                  # k3d cluster → BigBang → wait for ready
task package:default # k3d cluster → deploy package from CWD → tests
```

## Remote development (EC2)

`scripts/ec2-dev.sh` provisions a spot EC2 instance with docker installed
(via `scripts/cloud-config.yaml`); k3d itself always runs on your
workstation and drives the instance's docker daemon through a docker
context.

```bash
# one-time per instance: EC2 instance + ssh alias (bb-dev) + docker context (bb-dev)
task aws:ec2

# then any workflow, switched to the instance with a single variable
task default DOCKER_CONTEXT=bb-dev
task package:default DOCKER_CONTEXT=bb-dev DISABLE_CORE=true

# tear down (instance, context, dev.yaml)
task aws:ec2:destroy
```

`DOCKER_CONTEXT=bb-dev` switches the whole workflow:

- `docker`/`k3d` commands target the instance's daemon (via `DOCKER_CONTEXT`)
- volume mounts (`BASE_MOUNT_DIR`) move to `/home/ubuntu` on the instance
- host-side commands (`COMMAND_PREFIX`) run over `ssh bb-dev`
- the k3d API server is published on the instance's public IP
  (`k3d.serverHost`, read from `dev.yaml`), so the `k3d-bb-helm` kubectl
  context that k3d writes locally works from your workstation — no
  kubeconfig copying or editing

Notes:

- `task aws:ec2` writes `dev.yaml` with the instance metadata and is a
  no-op while the instance is reachable
- instances self-terminate 8 hours after boot (`sudo crontab -r` on the
  instance to disable); the security group and key pair are reused across
  instances
- rerun `task aws:ec2` after your workstation IP changes to re-authorize
  it in the security group
- instance size/disk: `INSTANCE_TYPE` and `VOLUME_SIZE` env vars for
  `scripts/ec2-dev.sh`

## Package development

Run from a package repo checkout (package is detected from the git remote):

```bash
task -t /path/to/taskfiles/Taskfile.yml package:default DISABLE_CORE=true
task -t /path/to/taskfiles/Taskfile.yml package:deploy    # deploy current branch
task -t /path/to/taskfiles/Taskfile.yml package:upgrade   # released → branch upgrade test
task -t /path/to/taskfiles/Taskfile.yml package:test      # unit + e2e tests
task -t /path/to/taskfiles/Taskfile.yml package:info      # show detected package/path/namespace
```

Common variables: `DISABLE_CORE=true`, `TEST_VALUES=tests/test-sso-values.yaml`,
`EXTRA_VALUES="--set foo=bar"`, and `DOCKER_CONTEXT=bb-dev` to run any of the
above against the EC2 instance.

> These tasks now template the chart from `../chart` in this repo (bb-taskfiles is
> monorepo'd into bb-k3d), not a published OCI artifact.

## Multiple clusters on one host

`CLUSTER_NAME` switches which cluster the tasks target, so `k3d-create` no longer
deletes every cluster — only the named one:

```bash
task default                      # default cluster "bb-helm"
task k3d-create CLUSTER_NAME=bb-helm-b
```

The cluster name alone isn't enough: the subnet, host ports (80/443/6443), and the
pull-through registry are host-level singletons. For a second cluster, override the
colliding values (e.g. `cluster-b.yaml` passed via `EXTRA_ARGS`/`--values`):

```yaml
k3d:
  name: bb-helm-b
  apiPort: 6444
  publishPorts: false              # 80/443 are owned by the first cluster
  subnet: "172.29.0.0/16"
  metallb:
    addresses: "172.29.0.2-172.29.0.5"
  hostAliases:
    passthrough:
      ip: "172.29.0.4"
      hostnames: [keycloak.dev.bigbang.mil, vault.dev.bigbang.mil]
    public:
      ip: "172.29.0.3"
      hostnames: [gitlab.dev.bigbang.mil, ...]
registry1:
  shared: true                     # reuse one cache instead of a per-cluster registry
```

With `registry1.shared: true`, create the shared pull-through registry once:

```bash
k3d registry create repo1 --proxy-remote-url https://registry1.dso.mil \
  -v /home/rob/reg:/var/lib/registry
```

### A cluster per package

Naming the cluster after the package lets you keep several package dev environments
up at once (e.g. `keycloak` and `gitlab`) without `package:default` tearing down the
others. Run each from its package checkout:

```bash
# from the keycloak repo
task -t /path/to/dev/Taskfile.yml package:default CLUSTER_NAME=keycloak DISABLE_CORE=true

# from the gitlab repo (second cluster → override the host-level singletons)
task -t /path/to/dev/Taskfile.yml package:default CLUSTER_NAME=gitlab DISABLE_CORE=true \
  EXTRA_ARGS="--values cluster-gitlab.yaml"
```

`CLUSTER_NAME` flows through `package:default` → `k3d-create`, so delete/create is
scoped to that cluster and its kube context is `k3d-<package>`. The package name is
shown by `package:info`, so you can reuse it verbatim. Only the first cluster can
publish `80/443` — give each additional one its own `cluster-<name>.yaml` (see the
override values above) with a distinct `k3d.name`, `apiPort`, `subnet`,
`metallb.addresses`, `hostAliases`, `publishPorts: false`, and `registry1.shared: true`.

Note: the `*.dev.bigbang.mil` domain is shared via `/etc/hosts`, so only one BigBang
is reachable by hostname at a time; the external dependencies (`k3d-dependencies`
network and its databases) are also shared across clusters.

## Project Structure

```
├── Taskfile.yml          # Main taskfile (deployment, package workflows)
├── taskfiles/
│   ├── aws.yml           # EC2 instance, ssh config, docker context
│   ├── base.yml          # k3d cluster creation, deploy, remote-mode vars
│   └── util.yml          # Utilities (health, readme, ...)
└── scripts/
    ├── ec2-dev.sh        # EC2 provisioning (key pair, SG, spot instance)
    └── cloud-config.yaml # Instance cloud-init (docker, kernel tuning)
```

To see all available tasks run `task --list`.
