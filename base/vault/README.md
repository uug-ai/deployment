<!-- markdownlint-disable MD013 -->

# Vault base manifests

This directory holds the raw Kubernetes manifests for **Vault**. Vault receives
recordings from Kerberos Agents, stores recording metadata in MongoDB, and sends
recording bytes to storage providers configured through the Vault UI.

> **Scope of this README.** At the top level of this repository Vault is normally
> installed through **Kustomize** (see [`overlays/`](../../overlays) and
> [`README.kustomize.md`](../../README.kustomize.md)). This README documents the
> alternative: applying the manifests in this folder directly with `kubectl`.
> Use it when you want to install only Vault, inspect each object, or integrate
> these manifests into your own deployment tooling.

## What gets deployed

| File | Kind | Purpose |
| ---- | ---- | ------- |
| [`mongodb-configmap.yaml`](./mongodb-configmap.yaml) | `ConfigMap` | Supplies Vault's MongoDB connection, backend flavor, retry-write, and TLS settings. |
| [`kerberos-vault-deployment.yaml`](./kerberos-vault-deployment.yaml) | `Deployment` | Runs the Vault API and UI on container port `80`. |
| [`kerberos-vault-service.yaml`](./kerberos-vault-service.yaml) | `Service` | Exposes Vault on `NodePort` **30080**. A commented `LoadBalancer` variant is included. |
| [`data-filtering-deployment.yaml`](./data-filtering-deployment.yaml) | `Deployment` | Optional YOLO data-filtering worker. The default manifest requests one NVIDIA GPU. |

The matching `kerberos-vault` namespace is defined in
[`../namespaces/kerberos-vault.yaml`](../namespaces/kerberos-vault.yaml).

## Prerequisites

- A running Kubernetes cluster and `kubectl` configured to reach it.
- A MongoDB-compatible database reachable from the Vault pod.
- A storage provider such as MinIO, Amazon S3, Google Cloud Storage, or Azure
  Blob Storage. Configure it in the Vault UI after deployment.
- An NVIDIA-capable node and device plugin only when deploying the optional
  data-filtering worker with its default resource settings.

## MongoDB configuration

Vault imports every key from the `mongodb` ConfigMap through `envFrom`. The base
manifest connects to the in-cluster MongoDB service at `mongodb.mongodb`.

| Variable | Default here | Meaning |
| -------- | ------------ | ------- |
| `MONGODB_DATABASE_STORAGE` | `KerberosStorage` | Database where Vault stores recording metadata and configuration. |
| `MONGODB_URI` | unset | Complete MongoDB connection URI. When set, it takes precedence over component settings. |
| `MONGODB_HOST` | `mongodb.mongodb` | MongoDB host and optional port for component-based configuration. |
| `MONGODB_DATABASE_CREDENTIALS` | `admin` | Authentication database or auth source. |
| `MONGODB_USERNAME` / `MONGODB_PASSWORD` | `root` / `yourpassword` | Database credentials. Replace these demo values before deployment. |
| `MONGODB_FLAVOR` | `mongodb` | Backend compatibility mode: `mongodb` or `documentdb`. |
| `MONGODB_RETRY_WRITES` | `true` | Enables retryable writes for MongoDB. Vault always disables them for DocumentDB. |
| `MONGODB_TLS` | `false` | Enables TLS for the database connection. |
| `MONGODB_TLS_CA_FILE` | empty | Path to a mounted PEM CA bundle. A non-empty value also enables TLS. |
| `MONGODB_TLS_INSECURE_SKIP_VERIFY` | `false` | Disables certificate and hostname verification. Use only for isolated local testing. |

The ConfigMap also contains legacy Factory and Hub database names, but Vault uses
`MONGODB_DATABASE_STORAGE` for its own data.

> [!WARNING]
> ConfigMaps are not appropriate for production credentials. Move the MongoDB
> username, password, or credential-bearing URI to a Kubernetes `Secret` in a
> production deployment and expose those keys to the Vault container.

### MongoDB Atlas or another URI connection

Set `MONGODB_URI` in [`mongodb-configmap.yaml`](./mongodb-configmap.yaml). The
component settings are ignored when the URI is non-empty.

The Deployment's `wait-for-mongodb-before-starup` init container currently probes
the base service name `mongodb.mongodb:27017`. When using Atlas or another external
database, change that command to probe the external host and port, or replace it
with a readiness mechanism suitable for your environment. Otherwise Vault will
remain in `Init` even when its configured database is reachable.

### DocumentDB or MongoDB with a custom CA

For AWS DocumentDB, use a connection URI, set the flavor to `documentdb`, disable
retryable writes, and enable TLS:

```yaml
MONGODB_URI: "mongodb://<username>:<password>@<endpoint>:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
MONGODB_FLAVOR: "documentdb"
MONGODB_RETRY_WRITES: "false"
MONGODB_TLS: "true"
MONGODB_TLS_CA_FILE: "/certs/global-bundle.pem"
MONGODB_TLS_INSECURE_SKIP_VERIFY: "false"
```

Create a Secret from the trusted CA bundle:

```bash
kubectl create namespace kerberos-vault --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mongodb-ca \
  --from-file=global-bundle.pem \
  -n kerberos-vault
```

Then add the Secret volume and mount to
[`kerberos-vault-deployment.yaml`](./kerberos-vault-deployment.yaml):

```yaml
spec:
  template:
    spec:
      containers:
        - name: vault
          volumeMounts:
            - name: mongodb-ca
              mountPath: /certs
              readOnly: true
      volumes:
        - name: mongodb-ca
          secret:
            secretName: mongodb-ca
```

Also update or remove the MongoDB wait init-container as described above. For
Amazon DocumentDB, the shared Vault database client defaults component-based
authentication to `SCRAM-SHA-1` and does not enable MongoDB Stable API.

## Vault configuration

Relevant environment variables are defined directly on the Vault Deployment:

| Variable | Default here | Meaning |
| -------- | ------------ | ------- |
| `KERBEROS_LOGIN_USERNAME` / `KERBEROS_LOGIN_PASSWORD` | `root` / `kerberos` | Vault UI login. Change these demo credentials. |
| `MQTTURI` | `tcp://mqtt.kerberos.io:1883` | MQTT broker used for on-demand forwarding. |
| `MQTT_USERNAME` / `MQTT_PASSWORD` | empty | Optional MQTT credentials. |
| `CONTINUOUS_FORWARDING` | `false` | Enables forwarding for a chained Vault setup. |

Storage providers, integrations, and Vault accounts are configured through the
UI after the pod starts. See [`README.configure.md`](../../README.configure.md).

## Deploy with kubectl without Kustomize

The manifest files do not hard-code a namespace because Kustomize normally
injects it. When applying them directly, target the namespace explicitly.

```bash
# 1. Create the namespace.
kubectl apply -f ../namespaces/kerberos-vault.yaml

# 2. Review the database settings, then create the ConfigMap.
kubectl apply -n kerberos-vault -f ./mongodb-configmap.yaml

# 3. Deploy Vault and expose it through NodePort.
kubectl apply -n kerberos-vault -f ./kerberos-vault-deployment.yaml
kubectl apply -n kerberos-vault -f ./kerberos-vault-service.yaml
```

Verify the rollout:

```bash
kubectl get pods,svc -n kerberos-vault
kubectl rollout status deployment/vault -n kerberos-vault
kubectl logs -n kerberos-vault deploy/vault
```

If the pod remains in `Init`, inspect the database wait container:

```bash
kubectl logs -n kerberos-vault deploy/vault \
  -c wait-for-mongodb-before-starup
```

## Access the UI

With the `NodePort` service, Vault is reachable on port **30080** of any node:

```bash
kubectl get nodes -o wide
# Browse http://<node-ip>:30080

# Or use a local port-forward without exposing a node port.
kubectl port-forward -n kerberos-vault svc/vault-nodeport 8080:80
# Browse http://localhost:8080
```

Log in with the configured `KERBEROS_LOGIN_USERNAME` and
`KERBEROS_LOGIN_PASSWORD` values. The base defaults are `root` and `kerberos`.

To use a cloud `LoadBalancer`, uncomment the `vault-lb` service at the bottom of
[`kerberos-vault-service.yaml`](./kerberos-vault-service.yaml) and remove or
comment out the `NodePort` service.

## Optional data filtering

The data-filtering worker is independent of the Vault Deployment. Before applying
it, configure its queue, Vault credentials, model settings, and GPU resources in
[`data-filtering-deployment.yaml`](./data-filtering-deployment.yaml).

```bash
kubectl apply -n kerberos-vault -f ./data-filtering-deployment.yaml
kubectl rollout status deployment/data-filtering -n kerberos-vault
```

Clusters without an NVIDIA device plugin must remove the `nvidia.com/gpu`
requests and limits or leave this optional Deployment unapplied. See
[`README.extensions.md`](../../README.extensions.md) for the integration flow.

## Uninstall

```bash
kubectl delete -n kerberos-vault -f ./data-filtering-deployment.yaml --ignore-not-found
kubectl delete -n kerberos-vault -f ./kerberos-vault-service.yaml
kubectl delete -n kerberos-vault -f ./kerberos-vault-deployment.yaml
kubectl delete -n kerberos-vault -f ./mongodb-configmap.yaml
kubectl delete secret mongodb-ca -n kerberos-vault --ignore-not-found
kubectl delete -f ../namespaces/kerberos-vault.yaml
```
