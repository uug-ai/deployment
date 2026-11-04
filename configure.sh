#!/bin/bash

# Function to get the current network interface IP
get_ip_address() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1
}

# Parse command line arguments
command=$1
shift
while getopts ":s:i:" opt; do
  case $opt in
    s) storage_path="$OPTARG"
    ;;
    i) ip_address="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$command" == "apply" ]; then
  if [ -z "$storage_path" ]; then
    echo "Usage: $0 apply -s <storage_path> [-i <ip_address>]"
    exit 1
  fi

  if [ -z "$ip_address" ]; then
    ip_address=$(get_ip_address)
  fi

  # Make a local copy of kustomization.yaml
  cp ./overlays/microk8s/kustomization.yaml ./kustomization.yaml

  # Replace placeholders in the local copy of kustomization.yaml
  sed -i "s|localhost|$ip_address|g" ./kustomization.yaml
  sed -i "s|/media/Storage|$storage_path|g" ./kustomization.yaml

  # Adjust the base path reference
  sed -i "s|../../base|./base|g" ./kustomization.yaml

  bash scripts/install-garage.sh --prepare-only || exit 1

  # Apply kustomize installation
  kubectl kustomize ./ --enable-helm --load-restrictor LoadRestrictionsNone | kubectl apply -f -

  # Clean up the local copy
  rm ./kustomization.yaml

elif [ "$command" == "delete" ]; then
  # Make a local copy of kustomization.yaml
  cp ./overlays/microk8s/kustomization.yaml ./kustomization.yaml

  # Adjust the base path reference
  sed -i "s|../../base|./base|g" ./kustomization.yaml

  # Delete kustomize installation
  kubectl kustomize ./ --enable-helm --load-restrictor LoadRestrictionsNone | kubectl delete -f -

  # Clean up the local copy
  rm ./kustomization.yaml

else
  echo "Usage: $0 {apply|delete} [-s <storage_path>] [-i <ip_address>]"
  exit 1
fi