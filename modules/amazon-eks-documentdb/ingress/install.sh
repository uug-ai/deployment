#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INGRESS_NGINX_VERSION="4.15.1"
readonly CERT_MANAGER_VERSION="v1.21.1"

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    exit 1
  fi
done

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update ingress-nginx jetstack

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "${INGRESS_NGINX_VERSION}" \
  --namespace ingress-nginx \
  --create-namespace \
  --values "${SCRIPT_DIR}/ingress-nginx-values.yaml" \
  --atomic \
  --wait \
  --timeout 15m

helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --atomic \
  --wait \
  --timeout 15m

kubectl apply --filename "${SCRIPT_DIR}/cluster-issuer.yaml"
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-prod --timeout=2m
kubectl apply --filename "${SCRIPT_DIR}/hub-ingresses.yaml"

kubectl get service ingress-nginx-controller \
  --namespace ingress-nginx \
  --output jsonpath='Load balancer: {.status.loadBalancer.ingress[0].hostname}{"\n"}'
