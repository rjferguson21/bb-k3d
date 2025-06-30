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

helm template chart --set=registry1.username=$REGISTRY1_USERNAME \
                --set=registry1.password=$REGISTRY1_PASSWORD > dist/bootstrap.yaml

helm template chart --set=registry1.username=$REGISTRY1_USERNAME \
                --set=registry1.password=$REGISTRY1_PASSWORD \
                --show-only=k3d-config.yaml > dist/k3d.yaml                            

k3d cluster delete --config dist/k3d.yaml && k3d cluster create --config dist/k3d.yaml

helm upgrade --install bigbang $BIGBANG_DIR/chart \
  --namespace=bigbang --create-namespace \
  --values $BIGBANG_DIR/tests/test-values.yaml \
  --values $BIGBANG_DIR/chart/ingress-certs.yaml \
  --set=registryCredentials.username=$REGISTRY1_USERNAME
```