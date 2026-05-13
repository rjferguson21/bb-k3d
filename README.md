## Overview

This helm chart serves two main purposes:

1. **Bootstrap Configuration Generation**
   - Generates a `bootstrap.yaml` containing Flux and MetalLB configurations
   - MetalLB configuration is dependent on the `hostAliases` defined in the k3d config
   - The load balancer IPs configured here will be used by Big Bang for service exposure

2. **K3D Cluster Configuration**
   - Generates a `k3d.yaml` configuration file
   - Defines `hostAliases` that are critical for MetalLB's operation
   - These host entries ensure proper DNS resolution for the load balancer IPs
   - Used to create and manage local K3D clusters

The relationship between these configurations is important:
- The k3d config's `hostAliases` must be properly configured to match the MetalLB IP ranges
- These IPs will be used by Big Bang for exposing services
- Both configurations must be in sync for proper load balancer operation

## Build K3D config + flux/metallb bootstrap.yaml (see `deploy.sh`)
```sh
BIGBANG_DIR=/home/rob/bb/bigbang

helm template oci://ghcr.io/rjferguson21/bb-k3d:0.2.10 > dist/bootstrap.yaml
helm template oci://ghcr.io/rjferguson21/bb-k3d:0.2.10 \
  --set=k3d.volumeBaseDir=$(pwd)/dist \
  --set-string=registry1.username="${REGISTRY1_USERNAME}" \
  --set-string=registry1.password="${REGISTRY1_PASSWORD}" \
  --show-only=templates/k3d-config.yaml > dist/k3d.yaml

k3d cluster delete --config dist/k3d.yaml && k3d cluster create --config dist/k3d.yaml

# Install BigBang
helm upgrade --install bigbang $BIGBANG_DIR/chart \
  --namespace=bigbang --create-namespace \
  --values $BIGBANG_DIR/tests/test-values.yaml \
  --values $BIGBANG_DIR/chart/ingress-certs.yaml
```

## macOS local flow

The default chart values target a Linux host. For macOS, use the files under
`mac/` to map host ports through the k3d load balancer and mount a generated
machine-id file instead of `/etc/machine-id`.

```sh
source ./mac/source-registry-creds.sh
cd mac
task build:cluster
task create:cluster
task deploy:bigbang
```

See `mac/README.md` for the full workflow and cleanup commands.
