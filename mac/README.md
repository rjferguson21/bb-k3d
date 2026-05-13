# macOS local dev flow (Istio + Kyverno)

This folder provides a minimal, local-first K3D + Big Bang flow for macOS.
It uses a load balancer port mapping so hostnames like `neuvector.dev.bigbang.mil`
resolve on your Mac when mapped to `127.0.0.1`.

## Prereqs

- Docker Desktop
- k3d
- kubectl
- helm
- yq
- task
- registry1.dso.mil credentials

## One-time host file update

Add this entry to `/etc/hosts` on your Mac:

```
127.0.0.1 neuvector.dev.bigbang.mil
```

## Required env vars

These are used to create the local registry proxy and the `private-registry` secret
in the bootstrap manifest:

```
export REGISTRY1_USERNAME="..."
export REGISTRY1_PASSWORD="..."
# optional
export REGISTRY1_EMAIL="..."
```

Or source them directly from your overrides file:

```bash
source ./mac/source-registry-creds.sh
```

Optional custom path:

```bash
source ./mac/source-registry-creds.sh /path/to/registryOverrides.yaml
```

## Run the flow

From this directory:

```
cd bb-k3d/mac

task build:cluster
task create:cluster
task deploy:bigbang
```

The `create:cluster` task writes a repo-local kubeconfig at `../dist/kubeconfig.yaml`.
Use it explicitly if your default kubeconfig is not updated:

```bash
export KUBECONFIG="$(pwd)/../dist/kubeconfig.yaml"
```

### Optional: keep overrides in a separate file

If you want to keep `mac/values.yaml` clean, pass an extra values file that only contains
your `overrides:` block (or any other bb-k3d values):

```
EXTRA_VALUES_FILE=mac/overrides/neuvector.yaml task build:cluster
```

The `create:cluster` task also creates:

- `dist/cypress/` (required mount path)
- `dist/machine-id` (macOS replacement for `/etc/machine-id`)

## Secrets override file

This flow expects your existing secrets file at:

```
../overrides/registryOverrides.yaml
```

It is passed to the Big Bang install as a `--values` file.

## What gets deployed

- Istio (CRDs, istiod, gateways)
- Kyverno + Kyverno policies

Neuvector is present in the example host mapping but disabled in `mac/values.yaml` by
default so the local footprint stays small. Enable it with an extra values file when
you need to test that package specifically.

Everything else is disabled via `mac/values.yaml` overrides for a minimal footprint.

## Cleanup

```
cd bb-k3d/mac

task teardown:cluster
task delete:cluster
```

`teardown:cluster` removes only the k3d cluster.  
`delete:cluster` removes generated files but keeps `dist/reg` as a local registry cache.
