###############################################################################
# DocumentDB
#
# The cluster is created with TLS (encryption in transit) and encryption at
# rest enabled. Clients must trust the Amazon RDS certificate authority bundle:
#
#   curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
#
# For Kerberos Hub that bundle is mounted through the helm chart's
# `mongodb.tls` values, see the README next to this file.
###############################################################################

resource "random_password" "docdb" {
  count = var.docdb_password == null ? 1 : 0

  length  = 32
  special = true

  # DocumentDB rejects '/', '"' and '@' in the master password. '@' and '/'
  # would also break the MongoDB connection string.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  docdb_password          = var.docdb_password != null ? var.docdb_password : random_password.docdb[0].result
  docdb_subnet_group_name = "${local.name}-docdb-${module.vpc.vpc_id}"
}

resource "aws_security_group" "docdb" {
  name        = "${local.name}-docdb"
  description = "MongoDB wire protocol access to the Kerberos Hub DocumentDB cluster"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Name = "${local.name}-docdb" })
}

resource "aws_vpc_security_group_ingress_rule" "docdb_from_eks_nodes" {
  security_group_id = aws_security_group.docdb.id
  description       = "DocumentDB from the EKS worker nodes"

  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
}

resource "aws_vpc_security_group_ingress_rule" "docdb_from_cidrs" {
  for_each = toset(var.docdb_allowed_cidrs)

  security_group_id = aws_security_group.docdb.id
  description       = "DocumentDB from ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = 27017
  to_port     = 27017
}

resource "aws_docdb_subnet_group" "this" {
  name        = local.docdb_subnet_group_name
  description = "Private subnets of the Kerberos Hub VPC"
  subnet_ids  = module.vpc.private_subnets

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_docdb_cluster_parameter_group" "this" {
  name        = "${local.name}-docdb"
  family      = var.docdb_parameter_group_family
  description = "Kerberos Hub DocumentDB parameters"

  parameter {
    name  = "tls"
    value = var.docdb_tls ? "enabled" : "disabled"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_docdb_cluster" "this" {
  cluster_identifier = "${local.name}-docdb"
  engine             = "docdb"
  engine_version     = var.docdb_engine_version
  port               = 27017

  master_username = var.docdb_username
  master_password = local.docdb_password

  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.this.name
  vpc_security_group_ids          = [aws_security_group.docdb.id]

  storage_encrypted = true
  kms_key_id        = var.docdb_kms_key_id

  backup_retention_period      = var.docdb_backup_retention_period
  preferred_backup_window      = "02:00-04:00"
  preferred_maintenance_window = "sun:04:30-sun:05:30"

  enabled_cloudwatch_logs_exports = var.docdb_enabled_cloudwatch_logs_exports

  deletion_protection       = var.docdb_deletion_protection
  skip_final_snapshot       = var.docdb_skip_final_snapshot
  final_snapshot_identifier = var.docdb_skip_final_snapshot ? null : "${local.name}-docdb-final"

  tags = local.tags

  lifecycle {
    replace_triggered_by = [aws_docdb_subnet_group.this.name]
  }
}

resource "aws_docdb_cluster_instance" "this" {
  count = var.docdb_instance_count

  identifier         = "${local.name}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.docdb_instance_class

  auto_minor_version_upgrade = true

  tags = local.tags
}
