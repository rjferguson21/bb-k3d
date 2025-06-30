#!/bin/bash

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