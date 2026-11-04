# Factory — base manifests

This directory holds the raw Kubernetes manifests for **Factory**. Factory
is a web application that runs *inside* your cluster and uses the Kubernetes API to
deploy, configure and observe Agents (one Deployment + Service per camera).

> **Scope of this README.** At the top level of this repository Factory is normally
> installed through **Kustomize** (see [`overlays/`](../../overlays) and the
> [`README.kustomize.md`](../../README.kustomize.md)). This README documents the
> alternative: applying the manifests in this folder **directly with `kubectl`**,
> without Kustomize. Use it when you want to install only Factory, understand each
> object in isolation, or integrate these manifests into your own tooling.

## What gets deployed

| File | Kind | Purpose |
| ---- | ---- | ------- |
| [`kerberos-factory-deployment.yaml`](./kerberos-factory-deployment.yaml) | `Deployment` | Hardened `ghcr.io/uug-ai/factory:v2.0.13`, pinned to its verified multi-architecture digest, container port `8080`. |
| [`kerberos-factory-service.yaml`](./kerberos-factory-service.yaml) | `Service` | Exposes Factory on `NodePort` **30079** (a `LoadBalancer` variant is included, commented out). |
| [`kerberos-factory-clusterrole.yaml`](./kerberos-factory-clusterrole.yaml) | `ClusterRole` + `ClusterRoleBinding` | Grants the `default` ServiceAccount in `kerberos-factory` the API access Factory needs to manage Agents. |

The matching namespace (`kerberos-factory`) is defined one level up in
[`../namespaces/kerberos-factory.yaml`](../namespaces/kerberos-factory.yaml).

## Configuration (ConfigMap store + Kubernetes engine)

These manifests are configured to run Factory **without MongoDB**. Factory keeps its
own (global/template) configuration and delivers each Agent's configuration through
Kubernetes **ConfigMaps**, and schedules Agents with the **Kubernetes** engine. This
is controlled by two environment variables on the Deployment:

```yaml
- name: FACTORY_CONFIGURATION
  value: "configmap"      # store config in ConfigMaps (json | configmap | secret | mongodb)
- name: FACTORY_ENGINE
  value: "kubernetes"     # schedule agents as Deployments (kubernetes | docker | host)
```

On start-up Factory bootstraps two cluster ConfigMaps — `agent-global-config`
(settings every Agent inherits) and `agent-template-config` (the base used for new
Agents) — and creates a per-agent `<name>-config` ConfigMap for each Agent it
provisions. **This is why the ClusterRole includes `configmaps`** — without that
permission the bootstrap fails.

Other relevant environment variables:

| Variable | Default here | Meaning |
| -------- | ------------ | ------- |
| `KERBEROS_LOGIN_USERNAME` / `KERBEROS_LOGIN_PASSWORD` | `root` / `kerberos` | Factory UI login. **Change these for anything but a demo.** |
| `KERBEROS_AGENT_IMAGE` | `kerberos/agent:latest` | Image used when Factory creates an Agent. |
| `KERBEROS_AGENT_MEMORY_LIMIT` | `256Mi` | Default memory limit for created Agents. |
| `NAMESPACE` | `kerberos-factory` | Namespace Factory schedules Agents into. |
| `PORT` | `8080` | Unprivileged HTTP listener used by the hardened image. |
| `K8S_PROXY` | `http://localhost:8080` | Internal proxy address Factory calls for the `/kubernetes` API. |

### Agent image compatibility

Factory's own port `8080` does not determine the HTTP port of the Agents it
creates. Published Agent releases still use port `80`; the forthcoming hardened
Agent image moves to `8080`. Before changing `KERBEROS_AGENT_IMAGE`, pin a
verified image tag or digest and confirm that the Factory version in use
generates compatible Agent container ports, Service target ports and any HTTP
probes. Existing Agent resources may need a coordinated update as well.
Do not assume changing this environment variable or pulling `latest` migrates
those resources. See the [Agent port migration guidance](../../README.md#agent-http-port-compatibility).

## Hardened runtime and upgrades

The image runs as UID/GID `65532:65532`, with a read-only root filesystem,
all Linux capabilities dropped, privilege escalation disabled and the
`RuntimeDefault` seccomp profile. The UI login named `root` is independent
of the container's operating-system user.

Two disk-backed `emptyDir` volumes are writable:

- `/home/factory/config` receives missing seed configuration files.
- `/tmp` is scratch space, including multipart uploads.

The pod's `fsGroup: 65532` makes these volumes writable without a root
init container. They survive a container restart but are replaced with the
pod. In this base's `configmap` mode, the global configuration is restored
from the existing Kubernetes ConfigMap on startup; existing global/template
ConfigMaps are not overwritten by image defaults. Keep the existing
ServiceAccount token and RBAC: Factory manages Agents through the Kubernetes
API even though its process is non-root.

Apply the Deployment and Service together when upgrading from a legacy
port-80 image. The external Service port `80` and NodePort `30079` are unchanged;
the Service now targets the named `http` port on container port `8080`.
Startup, readiness and liveness probes use `/healthz`; this endpoint checks
the HTTP process, not all downstream Kubernetes dependencies.

Back up any legacy configuration stored only in the old container before
replacing its pod. For `FACTORY_CONFIGURATION=json`, replace the config
`emptyDir` with a writable PVC and preserve its existing JSON files before
upgrading. A PVC must support access by UID/GID `65532`; storage backends that
do not honor `fsGroup` need matching permissions provisioned separately.

CI upgrades the last legacy release (`v2.0.11`) to these actual base manifests
on kind. It checks the restricted runtime, Service routing, UI/login,
ConfigMap bootstrap, saving settings and persistence after pod replacement.
The [smoke test](../../scripts/check-factory.sh) changes settings and restarts
Factory, so it refuses non-CI invocation and is intended only for disposable
test clusters.

## Prerequisites

- A running Kubernetes cluster and a `kubectl` configured to reach it.
- Permission to create `ClusterRole`/`ClusterRoleBinding` (cluster-admin or equivalent).

## Deploy with `kubectl` (without Kustomize)

The manifest files do **not** hard-code a namespace (Kustomize injects it at the upper
level). When applying directly, target the namespace explicitly with `-n`.

```bash
# 1. Create the namespace (only needed if it does not exist yet)
kubectl apply -f ../namespaces/kerberos-factory.yaml

# 2. Create the RBAC. The ClusterRole/ClusterRoleBinding are cluster-scoped;
#    the binding's subject already references the kerberos-factory namespace.
kubectl apply -f ./kerberos-factory-clusterrole.yaml

# 3. Deploy Factory and its service into the namespace
kubectl apply -n kerberos-factory -f ./kerberos-factory-deployment.yaml
kubectl apply -n kerberos-factory -f ./kerberos-factory-service.yaml
```

Or apply the whole folder at once (RBAC is cluster-scoped, the rest lands in the
namespace):

```bash
kubectl apply -f ../namespaces/kerberos-factory.yaml
kubectl apply -n kerberos-factory -f ./
```

Verify the rollout:

```bash
kubectl get pods,svc -n kerberos-factory
kubectl rollout status deployment/factory -n kerberos-factory
kubectl logs -n kerberos-factory deploy/factory
```

You should see log lines confirming the global and template Agent ConfigMaps were
bootstrapped.

## Access the UI

With the `NodePort` service, Factory is reachable on port **30079** of any node:

```bash
# Example: open http://<node-ip>:30079
kubectl get nodes -o wide        # find a node IP

# Or port-forward without exposing a node port
kubectl port-forward -n kerberos-factory svc/factory-nodeport 8080:80
# then browse http://localhost:8080
```

Log in with the `KERBEROS_LOGIN_USERNAME` / `KERBEROS_LOGIN_PASSWORD` values above
(default `root` / `kerberos`).

To use a cloud `LoadBalancer` instead of a `NodePort`, uncomment the `factory-lb`
service at the bottom of [`kerberos-factory-service.yaml`](./kerberos-factory-service.yaml)
and comment out the `NodePort` service.

## Switching the configuration store

ConfigMap storage is recommended for a clean, database-free install, but Factory
supports other stores via `FACTORY_CONFIGURATION`:

- `configmap` *(default here)* — config in ConfigMaps, no MongoDB.
- `secret` — same as `configmap` but sensitive values are kept in Kubernetes Secrets
  (add `secrets` to the ClusterRole resources for this mode).
- `json` — config in local JSON files, no MongoDB. Use a PVC at
  `/home/factory/config`; the default `emptyDir` is not durable across pods.
- `mongodb` — legacy behaviour: Factory and Agents read config from MongoDB. For this
  you also need a reachable MongoDB and the corresponding `MONGODB_*` environment
  variables (e.g. via a `mongodb` ConfigMap mounted with `envFrom`).

See the [Configuration & engines documentation](https://github.com/uug-ai/factory)
for the full model.

## Uninstall

```bash
kubectl delete -n kerberos-factory -f ./kerberos-factory-service.yaml
kubectl delete -n kerberos-factory -f ./kerberos-factory-deployment.yaml
kubectl delete -f ./kerberos-factory-clusterrole.yaml
# Optionally remove the agent ConfigMaps Factory created and the namespace
kubectl delete configmap -n kerberos-factory agent-global-config agent-template-config --ignore-not-found
kubectl delete -f ../namespaces/kerberos-factory.yaml
```
