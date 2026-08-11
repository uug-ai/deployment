# Amazon EKS + DocumentDB (Terraform)

Terraform stack that creates a **basic Kubernetes cluster (EKS) and a managed
MongoDB-compatible database (Amazon DocumentDB) on AWS**, wired together so
Kerberos Hub can be installed on it straight away.

It is primarily meant as a **reproducible test environment** for the DocumentDB
support in the [`hub` helm chart](https://github.com/kerberos-io/helm-charts),
in particular the `mongodb.tls.*` values that mount the Amazon RDS certificate
authority bundle. It is deliberately small and cheap, not a hardened production
landing zone.

## What it creates

```mermaid
flowchart LR
    subgraph VPC["VPC (10.20.0.0/16)"]
        subgraph Public["Public subnets"]
            NAT[NAT gateway]
            LB[Load balancers]
        end
        subgraph Private["Private subnets"]
            NODES[EKS managed node group]
            DOCDB[(DocumentDB cluster<br/>TLS enforced)]
        end
    end
    EKSCP[EKS control plane] --- NODES
    NODES -- "27017 / TLS" --> DOCDB
    NODES --> NAT
```

| Component | Details |
| --------- | ------- |
| VPC | Public + private subnets across 3 availability zones, internet gateway, NAT gateway |
| EKS | Managed control plane, one managed node group, `coredns`, `kube-proxy`, `vpc-cni`, `eks-pod-identity-agent` and `aws-ebs-csi-driver` add-ons (IRSA role included) |
| DocumentDB | Cluster + instances in the private subnets, encryption **at rest** (KMS) and **in transit** (`tls=enabled`), subnet group, cluster parameter group |
| Security | A dedicated security group that only allows port `27017` from the EKS worker node security group (plus any extra CIDRs you pass in) |

> [!IMPORTANT]
> DocumentDB has **no public endpoint**. It can only be reached from inside the
> VPC, which is why the workloads that talk to it must run on this cluster (or
> you must tunnel through a bastion host / VPN).

> [!WARNING]
> This stack costs money while it exists (EKS control plane, NAT gateway, EC2
> nodes, DocumentDB instances and storage). Run `terraform destroy` when you are
> done.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2, authenticated with permissions to create VPC, EKS, IAM and DocumentDB resources
- `kubectl` and `helm`

## Usage

```bash
cd deployment/modules/amazon-eks-documentdb

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

terraform init
terraform plan
terraform apply
```

Creating the cluster and the database takes a while (EKS and DocumentDB are
both slow to provision).

### Replacing the VPC

AWS cannot move a DocumentDB subnet group or cluster between VPCs. The subnet
group name therefore includes the VPC ID, allowing Terraform to create a new
group and replace the cluster when the VPC changes instead of attempting an
unsupported in-place subnet update.

Discard any saved plan created before a VPC replacement or configuration
change, then create and apply a fresh one:

```bash
rm -f tfplan
terraform plan -out=tfplan
terraform apply tfplan
```

> [!WARNING]
> Replacing the VPC also replaces the DocumentDB cluster. If it contains data,
> create and verify a snapshot before applying the plan; a final snapshot
> preserves the old data but is not restored into the replacement cluster
> automatically.

State is kept locally by default. For anything shared, add a backend, for
example:

```hcl
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "kerberos-hub/eks-documentdb.tfstate"
    region = "eu-west-1"
  }
}
```

### Connect kubectl

```bash
$(terraform output -raw update_kubeconfig_command)
kubectl get nodes
```

## Installing Kerberos Hub against DocumentDB

### 1. Create the certificate authority secret

DocumentDB presents a certificate signed by the Amazon RDS certificate
authority, so every client needs the bundle:

```bash
kubectl create namespace kerberos-hub

curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
kubectl create secret generic mongodb-ca \
  --from-file=global-bundle.pem \
  -n kerberos-hub
```

### 2. Generate the values

```bash
terraform output -raw hub_values_snippet > hub-documentdb-values.yaml
```

Which produces something like:

```yaml
mongodb:
  flavor: "documentdb"
  retryWrites: "false"
  uri: "mongodb://kerberos:...@kerberos-hub-docdb.cluster-xxxx.eu-west-1.docdb.amazonaws.com:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
  adminDatabase: "admin"
  authenticationMechanism: "SCRAM-SHA-1"
  tls:
    enabled: true
    existingSecret: "mongodb-ca"
    caFileName: "global-bundle.pem"
    mountPath: "/certs"
```

The chart mounts the bundle into every workload that talks to MongoDB, appends
`tls=true&tlsCAFile=/certs/global-bundle.pem` to the URI, and exposes
`MONGODB_TLS`, `MONGODB_TLS_CA_FILE` and `MONGODB_TLS_INSECURE_SKIP_VERIFY`
through the `mongodb-config` ConfigMap.

> [!NOTE]
> With DocumentDB you must configure the database through `mongodb.uri`, not
> through `mongodb.host` / `mongodb.username` / `mongodb.password`, so that the
> TLS parameters end up in the connection string that every service uses.

### 3. Install the chart

```bash
helm repo add kerberos https://charts.kerberos.io
helm install hub kerberos/hub \
  --version 0.127.0 \
  -n kerberos-hub \
  -f your-hub-values.yaml \
  -f hub-documentdb-values.yaml
```

The `hub_values_snippet` output contains credentials, so treat the generated
file as a secret and do not commit it.

### 4. Verify

```bash
kubectl logs -n kerberos-hub deploy/hub-api | head -50
kubectl exec -n kerberos-hub deploy/hub-api -- ls -l /certs
```

A one-off connectivity check from inside the cluster:

```bash
kubectl run mongosh --rm -it --restart=Never -n kerberos-hub \
  --image=mongodb/mongodb-community-server:7.0-ubi8 \
  --overrides='{"spec":{"volumes":[{"name":"ca","secret":{"secretName":"mongodb-ca"}}],"containers":[{"name":"mongosh","image":"mongodb/mongodb-community-server:7.0-ubi8","stdin":true,"tty":true,"command":["mongosh"],"args":["'"$(terraform output -raw mongodb_uri)"'&tls=true&tlsCAFile=/certs/global-bundle.pem"],"volumeMounts":[{"name":"ca","mountPath":"/certs"}]}]}}'
```

### 5. Import the example Hub data

This module has a separate DocumentDB import under [`database-import`](database-import).
It uses the chart-managed `mongodb-config`, mounts `mongodb-ca`, forces TLS with
the Amazon RDS CA bundle, and refuses to run unless the backend flavor is
`documentdb` with retryable writes disabled. Install Hub chart `0.127.0` or
newer before running it.

Run it after installing Hub:

```bash
./database-import/run.sh
```

The import is idempotent: it upserts two example users, one subscription and
five settings documents using fixed IDs, then verifies those records. It can be
rerun after deleting or replacing the DocumentDB cluster.

| Account | Password | Role |
| ------- | -------- | ---- |
| `example-user` | `example-password` | Hub owner |
| `example-application` | `example-password` | Admin application |

These are public example credentials. Do not use this seed data in a production
deployment.

## Public HTTPS ingress

The [`ingress`](ingress) package installs ingress-nginx behind an
internet-facing AWS Network Load Balancer, installs cert-manager, and creates
Let's Encrypt certificates for exactly these routes:

| Host | Service |
| ---- | ------- |
| `aws-app.kerberos.lol` | `hub-frontend-svc:80` |
| `aws-api.kerberos.lol` | `hub-api-svc:8081` |

Keep the Hub chart's global `ingress` value disabled. The module owns these two
Ingress resources so that enabling public access does not also expose the Hub
administration services.

Install the controllers and resources:

```bash
./ingress/install.sh
```

The cert-manager values use `1.1.1.1` and `8.8.8.8` for HTTP-01 self-checks.
This avoids waiting for the AWS VPC resolver if it cached an `NXDOMAIN` before
the public records were created. The override affects only cert-manager's ACME
self-checks; normal cluster DNS continues to use the VPC resolver.

The script prints the NLB hostname. Create both DNS records as CNAMEs pointing
to that hostname. You can retrieve it again with:

```bash
kubectl get service ingress-nginx-controller \
  --namespace ingress-nginx \
  --output jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

| DNS name | Type | Target |
| -------- | ---- | ------ |
| `aws-app.kerberos.lol` | CNAME | The ingress-nginx NLB hostname |
| `aws-api.kerberos.lol` | CNAME | The ingress-nginx NLB hostname |

cert-manager automatically retries its HTTP-01 challenges after DNS resolves;
do not delete pending CertificateRequests. Wait for both certificates:

```bash
kubectl wait --namespace kerberos-hub \
  --for=condition=Ready certificate/aws-app-kerberos-lol-tls \
  certificate/aws-api-kerberos-lol-tls \
  --timeout=10m
```

Set Hub's public URLs with the non-secret values fragment after the certificates
are ready. Include the same private Hub and DocumentDB values used for the
original installation:

```bash
helm upgrade hub kerberos/hub \
  --version 0.127.0 \
  --namespace kerberos-hub \
  --file your-hub-values.yaml \
  --file hub-documentdb-values.yaml \
  --file ingress/hub-public-values.yaml \
  --atomic \
  --wait
```

Verify both public endpoints:

```bash
curl --fail https://aws-api.kerberos.lol/health
curl --fail --output /dev/null https://aws-app.kerberos.lol/login
```

## Persistent volumes

The EBS CSI driver is installed, but EKS ships `gp2` as the default storage
class. To use `gp3` instead:

```bash
kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
EOF
```

## Tear down

```bash
# Remove Kubernetes resources first so AWS load balancers and volumes are cleaned up.
kubectl delete -f ingress/hub-ingresses.yaml --ignore-not-found
helm uninstall hub -n kerberos-hub
kubectl delete -f ingress/cluster-issuer.yaml --ignore-not-found
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx

terraform destroy
```

## Inputs

The defaults are tuned for a small test stack. See [variables.tf](variables.tf)
for the full list; the ones you are most likely to change:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `name` | `kerberos-hub` | Name prefix for every resource |
| `region` | `eu-west-1` | AWS region |
| `vpc_cidr` | `10.20.0.0/16` | VPC CIDR block |
| `single_nat_gateway` | `true` | One shared NAT gateway (cheaper, not highly available) |
| `kubernetes_version` | `1.31` | EKS control plane version |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | Who may reach the Kubernetes API, **narrow this down** |
| `node_instance_types` | `["t3.large"]` | Worker node instance types |
| `node_desired_size` | `2` | Number of worker nodes |
| `docdb_instance_class` | `db.t3.medium` | DocumentDB instance class |
| `docdb_instance_count` | `1` | Number of DocumentDB instances |
| `docdb_username` | `kerberos` | Master username |
| `docdb_password` | generated | Master password, generated when unset |
| `docdb_tls` | `true` | Enforce TLS on the cluster |
| `docdb_allowed_cidrs` | `[]` | Extra CIDRs allowed on port 27017 |

## Outputs

| Output | Description |
| ------ | ----------- |
| `cluster_name`, `cluster_endpoint` | EKS cluster identity |
| `update_kubeconfig_command` | Ready to run `aws eks update-kubeconfig ...` |
| `vpc_id`, `private_subnet_ids` | Networking identifiers |
| `docdb_endpoint`, `docdb_reader_endpoint`, `docdb_port` | DocumentDB connection details |
| `docdb_username`, `docdb_password` | Master credentials (password is sensitive) |
| `mongodb_uri` | Connection string for `mongodb.uri` (sensitive) |
| `hub_values_snippet` | Ready to paste helm values including the TLS block (sensitive) |

## Related

- [`../amazon-documentdb`](../amazon-documentdb/README.md) — using DocumentDB as the Kerberos Hub metadata store
- [`../../overlays/documentdb`](../../overlays/documentdb) — Kustomize overlay that deploys Kerberos Hub against DocumentDB
- [`../../README.k8s-managed.md`](../../README.k8s-managed.md) — installing on managed Kubernetes
