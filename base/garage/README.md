# Garage S3 for local Kubernetes deployments

The default Kubernetes stack uses [Garage](https://garagehq.deuxfleurs.fr/),
not the MinIO operator. The pinned multi-architecture `dxflrs/garage:v2.5.0`
image runs as a single non-root node with SQLite metadata and object data on
the same 10Gi `ssd-hostpath` PVC. This is a local/edge/CI example with **no
replication or high availability**, not a production multi-node layout.
Use Garage's [production deployment guide](https://garagehq.deuxfleurs.fr/documentation/cookbook/real-world/)
for replicated storage. Choose capacity and a backup policy before storing
recordings; resizing a bound PVC depends on your storage provisioner.

## Install

First install your storage provisioner and create the `ssd-hostpath`
StorageClass (the same prerequisite used by MongoDB and RabbitMQ). Run commands
from the deployment repository root:

```sh
bash scripts/install-garage.sh
bash scripts/check-garage.sh
```

The installer generates an RPC secret and S3 credentials in the Kubernetes
Secret `garage/garage-credentials`, and reuses them on subsequent runs. No
credentials are committed to the repository. Garage's `--single-node` and
`--default-bucket` startup flags initialize the layout and `mybucket`.
The installer refuses to generate new credentials if the PVC already exists
but its Secret is missing: restore the original Secret instead.

For a full Kustomize installation, prepare credentials before applying the
overlay; the default base already includes Garage:

```sh
bash scripts/install-garage.sh --prepare-only
kubectl kustomize overlays/microk8s --enable-helm --load-restrictor LoadRestrictionsNone | kubectl apply -f -
kubectl -n garage rollout status statefulset/garage --timeout=300s
```

The `configure.sh apply` helper also prepares the Secret before applying its
overlay. Back up the Secret and the PVC together. Do not delete the namespace,
Secret or PVC as an upgrade/recovery step.

## Configure Vault

Add a storage provider using Vault's existing **MinIO/S3-compatible provider
type**. The provider *name* identifies the instance and is distinct from its
implementation type:

| Setting | Value |
| --- | --- |
| Provider type | MinIO (`minio`) |
| Provider name | `garage` |
| Bucket | `mybucket` |
| Region | `garage` |
| Internal hostname | `garage.garage:3900` (no URL scheme) |
| SSL | Disabled for this local HTTP example |
| Access key | Secret field `access-key` |
| Secret key | Secret field `secret-key` |

Retrieve credentials locally when configuring Vault; do not paste them into
logs, issues, or committed values:

```sh
kubectl -n garage get secret garage-credentials -o jsonpath='{.data.access-key}' | base64 --decode
kubectl -n garage get secret garage-credentials -o jsonpath='{.data.secret-key}' | base64 --decode
```

The S3 endpoint is exposed at `http://NODE_IP:30090`. If browsers or remote
clients consume provider-native presigned URLs, configure Vault's external
hostname as `NODE_IP:30090` with external SSL disabled (or a real TLS endpoint).
Cluster-only DNS names cannot be resolved by external clients. Protect exposed
ports with firewall rules and use TLS outside a trusted local network. Garage's
RPC port is bound to loopback; no admin API or web console is exposed.

Set the Vault account's main provider to `garage`. The supplied Hub values
also use that name for recording, archive, thumbnail and sprite access.
**Vault account credentials are separate from Garage S3 credentials**: keep
the existing Agent/Hub account credentials aligned with the Vault account,
not with the generated S3 key.

## Verification

`scripts/check-garage.sh` performs an authenticated AWS Signature V4 PUT/GET
through the Kubernetes Service and compares object bytes. It retains a small,
uniquely named object under `mybucket/ci-smoke/`; it never deletes existing
objects. The optional `--restart` flag restarts the Garage pod between upload
and download to verify persistence; use it only in CI or a maintenance window.
CI also verifies that reinstalling Garage preserves its credential Secret.

## Existing MinIO installations

The [MinIO manifests](../minio/) remain available as an explicit legacy option.
This change does **not** copy recordings, modify Vault's stored provider
records, or delete MinIO resources. Do not use prune/apply cleanup to remove
the old backend while it contains recordings.

When upgrading an existing deployment, keep its existing Vault provider names
in the Hub values (`kerberosvault.provider`, `archive.provider`,
`thumbnail.provider`, `sprite.provider`) until recordings have been explicitly
migrated and reads verified. Add Garage as a separate provider/account as
needed. Treat object migration and retirement of MinIO as a separate,
backed-up operation; this installer only provisions the new backend.
