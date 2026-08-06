# Amazon DocumentDB

[Amazon DocumentDB](https://aws.amazon.com/documentdb/) is a managed, MongoDB
compatible database. It can be used as the metadata store for Kerberos Hub
instead of a self-hosted MongoDB.

## Things to know

- **Not reachable from outside its VPC.** DocumentDB has no public endpoint, so
  the Kerberos Hub services must run inside (or be peered with) the same VPC.
- **TLS is enabled by default.** Clients must trust the Amazon RDS certificate
  authority bundle:
  `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`.
- **Not every MongoDB feature is available.** Retryable writes, the MongoDB
  Stable API, geospatial queries/indexes and complex `$lookup` pipelines are
  unsupported. Set `mongodb.flavor: "documentdb"` and
  `mongodb.retryWrites: "false"` in the hub chart so those code paths are
  disabled.

## Provisioning

The [`amazon-eks-documentdb`](../amazon-eks-documentdb/README.md) Terraform
stack creates a VPC, an EKS cluster and a DocumentDB cluster with TLS enforced,
and outputs a ready to paste `mongodb` values block for the hub helm chart.

## Connecting Kerberos Hub

Configure the database through `mongodb.uri` (not `mongodb.host`) and point the
chart at the CA bundle:

```bash
curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
kubectl create secret generic mongodb-ca --from-file=global-bundle.pem -n kerberos-hub
```

```yaml
mongodb:
  flavor: "documentdb"
  retryWrites: "false"
  uri: "mongodb://<user>:<password>@<cluster>.docdb.amazonaws.com:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
  adminDatabase: "admin"
  authenticationMechanism: "SCRAM-SHA-1"
  tls:
    enabled: true
    existingSecret: "mongodb-ca"
    caFileName: "global-bundle.pem"
    mountPath: "/certs"
```

The chart mounts the bundle read-only into every workload that talks to
MongoDB and appends `tls=true&tlsCAFile=/certs/global-bundle.pem` to the
connection string.

## Related

- [`../amazon-eks-documentdb`](../amazon-eks-documentdb/README.md) — Terraform for EKS + DocumentDB
- [`../../overlays/documentdb`](../../overlays/documentdb) — Kustomize overlay using DocumentDB
