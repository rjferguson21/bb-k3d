#!/bin/bash
# Host-side SNI router for k3d clusters. Runs one nginx container on host ports
# 80/443 and forwards TLS connections, unterminated, to the target cluster's
# Istio ingress gateways based on the SNI hostname. With every *.dev.bigbang.mil
# name pointed at 127.0.0.1 in /etc/hosts, switching clusters is just re-running
# this script; nothing else on the host changes.
#
# Usage: ./router.sh <cluster-name>     # start or re-point at k3d-<cluster-name>
#        ./router.sh --stop             # remove the router container
set -euo pipefail

name="bb-k3d-router"
image="${ROUTER_IMAGE:-nginx:1.27-alpine}"
dir="${ROUTER_DIR:-$HOME/.cache/bb-k3d/router}"

if [ "${1:-}" = "--stop" ]; then
  docker rm -f "$name" >/dev/null 2>&1 && echo "removed $name" || echo "$name not running"
  exit 0
fi

cluster="${1:?usage: router.sh <cluster-name> | --stop}"
ctx="k3d-$cluster"
mkdir -p "$dir"

# Read the cluster straight from k3d so the router works from any directory,
# whatever KUBECONFIG points at.
KUBECONFIG=$(mktemp)
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT
k3d kubeconfig get "$cluster" >"$KUBECONFIG"

# Gateway services -> upstreams. Each istio=ingressgateway LoadBalancer becomes an
# upstream named after the service; the one containing "public" is the default.
gw_json=$(kubectl --context "$ctx" get svc -A -l istio=ingressgateway -o json)
upstreams=$(jq -r '.items[] | select(.status.loadBalancer.ingress[0].ip != null)
  | "\(.metadata.name) \(.status.loadBalancer.ingress[0].ip)"' <<<"$gw_json")
if [ -z "$upstreams" ]; then
  echo "no istio ingress gateway services with a LoadBalancer IP in context $ctx" >&2
  exit 1
fi
default_gw=$(awk '/public/ {print $1; exit}' <<<"$upstreams")
default_gw="${default_gw:-$(awk 'NR==1 {print $1}' <<<"$upstreams")}"

# Hostname -> gateway from VirtualServices bound to those gateways. Unmatched
# hostnames fall through to the default (public) gateway.
host_map=$(kubectl --context "$ctx" get virtualservices -A -o json | jq -r '
  .items[] | .spec.gateways[]? as $gw | .spec.hosts[]? as $h
  | select($h != "*") | "\($h) \($gw | split("/") | last)"' | sort -u)

conf="$dir/nginx.conf"
{
  echo "events { worker_connections 1024; }"
  echo
  echo "http {"
  echo "  server {"
  echo "    listen 80;"
  echo "    server_name _;"
  echo "    return 301 https://\$host\$request_uri;"
  echo "  }"
  echo "}"
  echo
  echo "stream {"
  echo "  map \$ssl_preread_server_name \$upstream {"
  echo "    hostnames;"
  while read -r host gw; do
    [ -n "$host" ] && printf '    %s %s;\n' "$host" "${gw//-/_}"
  done <<<"$host_map"
  printf '    default %s;\n' "${default_gw//-/_}"
  echo "  }"
  while read -r svc ip; do
    printf '  upstream %s { server %s:443; }\n' "${svc//-/_}" "$ip"
  done <<<"$upstreams"
  echo "  server {"
  echo "    listen 443;"
  echo "    ssl_preread on;"
  echo "    proxy_pass \$upstream;"
  echo "  }"
  echo "}"
} >"$conf"

# The config dir is bind-mounted (not the file) so rewrites are visible to the
# running container and a reload picks them up without a restart.
if docker ps --format '{{.Names}}' | grep -qx "$name"; then
  docker exec "$name" nginx -t -c /etc/nginx/router/nginx.conf >/dev/null 2>&1
  docker exec "$name" nginx -s reload 2>/dev/null
  action="re-pointed"
else
  docker rm -f "$name" >/dev/null 2>&1 || true
  # Host networking so the container can reach the MetalLB IPs on the k3d bridge.
  docker run -d --name "$name" --restart unless-stopped --network host \
    -v "$dir:/etc/nginx/router:ro" "$image" \
    nginx -c /etc/nginx/router/nginx.conf -g 'daemon off;' >/dev/null
  action="started"
fi

echo "$name $action -> $ctx"
awk '{printf "  %-28s %s\n", $1, $2}' <<<"$upstreams"
awk '{printf "  %-40s -> %s\n", $1, $2}' <<<"$host_map"
echo "  (other *.dev.bigbang.mil hosts -> $default_gw)"

# Everything above only helps if the hostnames resolve to loopback. Each gateway
# gets its own 127.0.0.x: browsers coalesce HTTP/2 connections across hostnames
# that share an IP and a cert (*.dev.bigbang.mil), and a coalesced connection
# keeps the SNI it was opened with, so a shared IP would send e.g. prometheus
# requests down the keycloak (passthrough) connection. CoreDNS NodeHosts carries
# the chart's full hostAliases list, grouped by gateway IP, so the block covers
# hosts any package might expose and never changes per cluster.
hosts_block=$(kubectl --context "$ctx" get cm -n kube-system coredns -o jsonpath='{.data.NodeHosts}' \
  | grep 'dev\.bigbang\.mil' | while read -r ip hosts; do
      gw=$(awk -v ip="$ip" '$2 == ip {print $1}' <<<"$upstreams")
      printf '%s %s\n' "${gw:-$ip}" "$(tr ' ' '\n' <<<"$hosts" | sort -u | tr '\n' ' ' | sed 's/ $//')"
    done | sort | awk '{ lo = ($1 ~ /public/) ? "127.0.0.1" : "127.0.0." (++n + 1); $1 = lo; print }')

missing=false
while read -r lo hosts; do
  first=${hosts%% *}
  grep -E "^$lo[[:space:]]" /etc/hosts | grep -qw "$first" || missing=true
done <<<"$hosts_block"

if $missing; then
  cat <<MSG

/etc/hosts does not map the dev.bigbang.mil names to the router's loopback
addresses (one per gateway). Replace any existing dev.bigbang.mil lines with this
block (one-time; it never changes per cluster):

  sudo sed -i '/dev.bigbang.mil/d' /etc/hosts
  printf '%s\n' $(sed "s/.*/'&'/" <<<"$hosts_block" | tr '\n' ' ') | sudo tee -a /etc/hosts
MSG
fi
