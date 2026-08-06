###############################################################################
# Cluster
###############################################################################

output "region" {
  description = "AWS region the stack is deployed in."
  value       = var.region
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "update_kubeconfig_command" {
  description = "Command to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "ID of the VPC. DocumentDB is only reachable from inside this VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets hosting the worker nodes and DocumentDB."
  value       = module.vpc.private_subnets
}

###############################################################################
# DocumentDB
###############################################################################

output "docdb_endpoint" {
  description = "Cluster (writer) endpoint of the DocumentDB cluster."
  value       = aws_docdb_cluster.this.endpoint
}

output "docdb_reader_endpoint" {
  description = "Reader endpoint of the DocumentDB cluster."
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "docdb_port" {
  description = "Port the DocumentDB cluster listens on."
  value       = aws_docdb_cluster.this.port
}

output "docdb_username" {
  description = "DocumentDB master username."
  value       = aws_docdb_cluster.this.master_username
}

output "docdb_password" {
  description = "DocumentDB master password. Read it with: terraform output -raw docdb_password"
  value       = local.docdb_password
  sensitive   = true
}

output "docdb_security_group_id" {
  description = "Security group guarding the DocumentDB cluster."
  value       = aws_security_group.docdb.id
}

output "docdb_tls_enabled" {
  description = "Whether TLS is enforced on the DocumentDB cluster."
  value       = var.docdb_tls
}

###############################################################################
# Kerberos Hub wiring
###############################################################################

output "mongodb_uri" {
  description = <<-EOT
    Connection string for the Kerberos Hub helm chart (`mongodb.uri`).
    The chart appends `tls=true` and `tlsCAFile=...` itself when
    `mongodb.tls.enabled=true`, so no TLS parameters are included here.
    Read it with: terraform output -raw mongodb_uri
  EOT

  value = format(
    "mongodb://%s:%s@%s:%d/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false",
    var.docdb_username,
    urlencode(local.docdb_password),
    aws_docdb_cluster.this.endpoint,
    aws_docdb_cluster.this.port,
  )

  sensitive = true
}

output "hub_values_snippet" {
  description = <<-EOT
    Ready to paste values for the Kerberos Hub helm chart. Write it to a file with:
      terraform output -raw hub_values_snippet > hub-documentdb-values.yaml
    It expects the Amazon RDS CA bundle to be available as the `mongodb-ca` secret:
      curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
      kubectl create secret generic mongodb-ca --from-file=global-bundle.pem -n kerberos-hub
  EOT

  value = <<-EOT
    mongodb:
      # DocumentDB does not support geospatial queries, complex $lookup
      # pipelines or retryable writes, hence the flavor and retryWrites below.
      flavor: "documentdb"
      retryWrites: "false"
      uri: "mongodb://${var.docdb_username}:${urlencode(local.docdb_password)}@${aws_docdb_cluster.this.endpoint}:${aws_docdb_cluster.this.port}/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
      adminDatabase: "admin"
      authenticationMechanism: "SCRAM-SHA-1"
      tls:
        enabled: ${var.docdb_tls}
        existingSecret: "mongodb-ca"
        caFileName: "global-bundle.pem"
        mountPath: "/certs"
  EOT

  sensitive = true
}
