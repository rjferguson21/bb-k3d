# CLAUDE.md - AI Assistant Context

This document provides context for AI assistants (like Claude) working on this project.

## Project Overview

**bb-k3d** is a Helm chart that bootstraps local K3D Kubernetes clusters optimized for running Big Bang (a DoD DevSecOps platform). It handles the complete setup of a local development environment including cluster configuration, networking, load balancing, and GitOps tooling.

### Key Purposes

1. **Bootstrap Configuration**: Generates `bootstrap.yaml` with Flux and MetalLB configurations
2. **K3D Cluster Config**: Generates `k3d.yaml` for cluster creation with proper networking and registry integration
3. **Local Development**: Provides a consistent local environment that mirrors Big Bang production setups

## Architecture

### Core Components

- **K3D Cluster**: Local Kubernetes cluster using k3s in Docker
- **Flux**: GitOps operator for continuous delivery
- **MetalLB**: Load balancer for exposing services on specific IPs
- **Nginx Router**: Optional SNI-based routing for HTTPS traffic (can be disabled via `nginx.enabled`)
- **Registry Proxy**: Local registry mirror for registry1.dso.mil (DoD Iron Bank)

### Network Architecture

The cluster uses a custom subnet (default `172.28.0.0/16`) with two key IP addresses:
- **Public Gateway IP** (`172.28.0.3`): Handles most Big Bang services
- **Passthrough Gateway IP** (`172.28.0.4`): Handles services requiring TLS passthrough (Keycloak, Vault)

These IPs are critical - they must be:
1. Defined in `k3d.hostAliases` for DNS resolution
2. Allocated by MetalLB for load balancing
3. Routed by nginx (if enabled) based on SNI

## Project Structure

```
bb-k3d/
├── chart/                          # Helm chart
│   ├── Chart.yaml                  # Chart metadata (version managed by release-please)
│   ├── values.yaml                 # Default configuration values
│   ├── templates/
│   │   ├── k3d-config.yaml        # K3D cluster configuration template
│   │   ├── nginx.yaml             # Nginx router (optional, gated by nginx.enabled)
│   │   ├── private-registry.yaml  # Registry1 credentials secret
│   │   ├── dev-values.yaml        # Big Bang dev values ConfigMap
│   │   └── metallb/               # MetalLB load balancer configs
│   ├── tests/                      # Helm unit tests
│   │   ├── k3d-config_test.yaml   # Tests for k3d config template
│   │   └── nginx_test.yaml        # Tests for nginx template
│   └── charts/                     # Chart dependencies
│       └── flux2-2.15.0.tgz       # Flux Helm chart
├── Taskfile.yml                    # Task automation (build, test, deploy)
├── README.md                       # User documentation
└── CLAUDE.md                       # This file
```

## Key Configuration Values

### k3d (chart/values.yaml)

```yaml
k3d:
  nodes: 3                           # Number of agent nodes
  image: "rancher/k3s:v1.33.3-k3s1"  # K3s version to use
  serverIP: "127.0.0.1"              # API server bind address
  subnet: "172.28.0.0/16"            # Cluster network subnet
  volumeBaseDir: "/home/rob"         # Host directory for volume mounts
  hostAliases:
    passthrough:
      ip: "172.28.0.4"               # IP for TLS passthrough services
      hostnames: [keycloak.dev.bigbang.mil, vault.dev.bigbang.mil]
    public:
      ip: "172.28.0.3"               # IP for standard services
      hostnames: [gitlab.dev.bigbang.mil, argocd.dev.bigbang.mil, ...]
```

### nginx (chart/values.yaml)

```yaml
nginx:
  enabled: false                     # Toggle nginx router deployment
```

### registry1 (chart/values.yaml)

```yaml
registry1:
  registry: "registry1.dso.mil"      # DoD Iron Bank registry
  username: ""                       # Set via environment variable
  password: ""                       # Set via environment variable
```

## Important Templates

### chart/templates/k3d-config.yaml
Generates the K3D cluster configuration. Key features:
- Uses `{{ .Values.k3d.image }}` for configurable K3s version
- Creates local registry proxy for registry1.dso.mil
- Configures host aliases for DNS resolution
- Mounts volumes for persistence and testing
- Disables traefik and servicelb (replaced by MetalLB)

### chart/templates/nginx.yaml
Optional nginx-based router for SNI routing. Features:
- Gated by `{{ .Values.nginx.enabled }}` flag
- HTTP -> HTTPS redirect on port 80
- TLS passthrough on port 443 using SNI
- Maps hostnames to appropriate backend gateway IPs
- Runs as DaemonSet with hostNetwork for direct port binding

### chart/templates/metallb/
MetalLB configuration for load balancing:
- `metal.yaml`: IPAddressPool and L2Advertisement resources
- `metallb-native.yaml`: Full MetalLB installation (if needed)

## Development Workflow

### Using Taskfile

The project uses [Task](https://taskfile.dev) for automation. To see all available tasks with descriptions:

```bash
task --list
```

## Testing

### Unit Tests
The project uses [helm-unittest](https://github.com/helm-unittest/helm-unittest) for testing templates.

Install the plugin:
```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
```

Run tests:
```bash
task test:unit
# or
helm unittest chart/
```

Test coverage includes:

- Default value rendering
- Custom configuration overrides
- Conditional resource rendering (nginx.enabled)
- Template syntax validation

### Linting

```bash
task test
# or
helm lint chart/
```

### End-to-End (E2E) Testing

E2E testing validates the entire workflow from chart generation to cluster deployment and Big Bang installation.

#### Prerequisites

1. **Required Tools**:
   - `k3d` (v5.0.0+)
   - `helm` (v3.0.0+)
   - `kubectl`
   - `task` (optional, for automation)
   - `docker` (for k3d)

2. **Registry Credentials**:

   Set environment variables for registry1.dso.mil access:

   ```bash
   export REGISTRY1_USERNAME="your-username"
   export REGISTRY1_PASSWORD="your-password"
   ```

#### Running E2E Tests

**Full Automated Test** (recommended):

```bash
task
```

This runs the complete workflow:

1. Clones Big Bang repository (if not present)
2. Runs helm lint
3. Generates bootstrap.yaml and k3d.yaml
4. Creates K3D cluster
5. Deploys bootstrap resources
6. (Optional) Deploys Big Bang

**Manual E2E Test**:

```bash
# 1. Generate configurations
helm template k3d chart/ > dist/bootstrap.yaml
helm template k3d chart/ \
  --set=k3d.volumeBaseDir=$(pwd)/dist \
  --set=registry1.username="${REGISTRY1_USERNAME}" \
  --set=registry1.password="${REGISTRY1_PASSWORD}" \
  --show-only=templates/k3d-config.yaml > dist/k3d.yaml

# 2. Create cluster
k3d cluster create --config dist/k3d.yaml

# 3. Wait for cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# 4. Deploy bootstrap resources
kubectl apply -f dist/bootstrap.yaml

# 5. Verify Flux is running
kubectl wait --for=condition=Ready pods -n flux-system --all --timeout=300s

# 6. Verify MetalLB is configured
kubectl get ipaddresspools -A
kubectl get l2advertisements -A

# 7. (Optional) Deploy Big Bang
helm upgrade --install bigbang dist/bigbang/chart \
  --namespace=bigbang --create-namespace \
  --values bigbang/tests/test-values.yaml
```

#### E2E Test Checklist

Use this checklist to verify a successful E2E deployment:

- [ ] **Chart Generation**
  - [ ] `helm lint chart/` passes
  - [ ] `helm template k3d chart/` generates valid YAML
  - [ ] `bootstrap.yaml` contains Flux and MetalLB resources
  - [ ] `k3d.yaml` contains valid k3d configuration

- [ ] **Cluster Creation**
  - [ ] K3D cluster creates without errors
  - [ ] All nodes are in Ready state
  - [ ] Custom subnet is configured (check `docker network ls`)
  - [ ] Registry proxy is running (`docker ps | grep repo1`)

- [ ] **Bootstrap Resources**
  - [ ] Flux namespace exists: `kubectl get ns flux-system`
  - [ ] Flux controllers are running: `kubectl get pods -n flux-system`
  - [ ] MetalLB is installed: `kubectl get pods -n metallb-system`
  - [ ] IPAddressPool is configured: `kubectl get ipaddresspool -A`
  - [ ] Registry secret exists: `kubectl get secret private-registry -n flux-system`

- [ ] **Networking**
  - [ ] DNS resolution works from inside cluster

    ```bash
    kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup gitlab.dev.bigbang.mil
    ```

  - [ ] MetalLB IPs are allocated

    ```bash
    kubectl get svc -A | grep LoadBalancer
    ```

  - [ ] (If nginx enabled) Nginx router is running

    ```bash
    kubectl get pods -n kube-system -l app=nginx-router
    ```

- [ ] **Registry Access**
  - [ ] Registry proxy is accessible from cluster

    ```bash
    kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://repo1:5000/v2/
    ```

  - [ ] Can pull images from registry1 through proxy

    ```bash
    kubectl run test --image=registry1.dso.mil/ironbank/opensource/nginx/nginx:1.25.3
    ```

- [ ] **Big Bang (if deployed)**
  - [ ] Big Bang namespace exists: `kubectl get ns bigbang`
  - [ ] GitRepository is synced: `kubectl get gitrepository -n bigbang`
  - [ ] HelmReleases are ready: `kubectl get helmrelease -n bigbang`
  - [ ] Services are accessible via LoadBalancer IPs

#### Common E2E Test Failures

**Cluster Creation Fails**:

- Check Docker is running and has sufficient resources
- Verify subnet doesn't conflict: `docker network ls`
- Ensure ports 80, 443, 6443 are available
- Check k3d logs: `k3d cluster list` and `docker logs k3s-bb-helm-server-0`

**Registry Authentication Fails**:

- Verify `REGISTRY1_USERNAME` and `REGISTRY1_PASSWORD` are set
- Test credentials: `docker login registry1.dso.mil`
- Check secret: `kubectl get secret private-registry -n flux-system -o yaml`

**Flux Controllers Not Starting**:

- Check image pull errors: `kubectl describe pod -n flux-system`
- Verify registry proxy: `docker logs k3d-repo1-0`
- Check private-registry secret exists in flux-system namespace

**MetalLB Not Allocating IPs**:

- Verify IPAddressPool exists: `kubectl get ipaddresspool -A`
- Check MetalLB speaker logs: `kubectl logs -n metallb-system -l component=speaker`
- Ensure IP range matches subnet configuration

**Services Not Accessible**:

- Check LoadBalancer IPs: `kubectl get svc -A | grep LoadBalancer`
- Verify host aliases in `/etc/hosts` or local DNS
- Test from inside cluster first, then from host
- (If nginx enabled) Check nginx router logs

#### Cleaning Up After E2E Tests

```bash
# Delete the cluster
k3d cluster delete bb-helm

# Remove generated files
rm -rf dist/

# (Optional) Remove Big Bang clone
rm -rf dist/bigbang
```

#### CI/CD E2E Testing

For automated E2E testing in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
e2e-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v3
    - name: Install k3d
      run: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    - name: Run E2E tests
      env:
        REGISTRY1_USERNAME: ${{ secrets.REGISTRY1_USERNAME }}
        REGISTRY1_PASSWORD: ${{ secrets.REGISTRY1_PASSWORD }}
      run: |
        task build:cluster
        task create:cluster
        kubectl wait --for=condition=Ready nodes --all --timeout=300s
        kubectl apply -f dist/bootstrap.yaml
        kubectl wait --for=condition=Ready pods -n flux-system --all --timeout=300s
    - name: Cleanup
      if: always()
      run: k3d cluster delete bb-helm
```

## Contributing Guidelines

When making changes:

1. **Maintain Template Compatibility**: Test with `helm template` before committing
2. **Update Tests**: Add/update unit tests in `chart/tests/` for template changes
3. **Don't Bump Versions**: release-please owns `chart/Chart.yaml` `version`, `CHANGELOG.md` and the README chart tag; it opens a release PR from merged PR titles
4. **Test Locally**: Run `task test` and `task test:unit` before committing
5. **Conventional PR Titles**: PRs are squash-merged and the title must be `feat:`, `fix:`, `deps:`, `chore:`, `docs:`, `ci:`, `refactor:` or `test:` (`!` for breaking); that drives the version bump and changelog
6. **Preserve Defaults**: Don't change default values without good reason; they're tuned for Big Bang

## Links & References

- **Big Bang**: https://repo1.dso.mil/big-bang/bigbang
- **K3D**: https://k3d.io/
- **Flux**: https://fluxcd.io/
- **MetalLB**: https://metallb.universe.tf/
- **Registry1 (Iron Bank)**: https://registry1.dso.mil/
- **Helm Unittest**: https://github.com/helm-unittest/helm-unittest
