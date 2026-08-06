###############################################################################
# General
###############################################################################

variable "name" {
  description = "Name prefix used for every resource created by this stack."
  type        = string
  default     = "kerberos-hub"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "The name must be lowercase, start with a letter and contain only letters, digits and dashes (3-31 characters)."
  }
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment label applied as a tag (for example test, staging, production)."
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block of the VPC. DocumentDB is only reachable from within this VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones to spread the subnets over. DocumentDB requires at least two."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 4
    error_message = "availability_zone_count must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per availability zone. Cheaper, but not highly available."
  type        = bool
  default     = true
}

###############################################################################
# EKS
###############################################################################

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API server publicly. Keep it on for a test cluster, restrict it with cluster_endpoint_public_access_cidrs."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint. Narrow this to your office/VPN range."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types of the managed node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "EBS volume size (GiB) of each worker node."
  type        = number
  default     = 50
}

###############################################################################
# DocumentDB
###############################################################################

variable "docdb_engine_version" {
  description = "DocumentDB engine version."
  type        = string
  default     = "5.0.0"
}

variable "docdb_parameter_group_family" {
  description = "Parameter group family matching the engine version (docdb5.0, docdb4.0, ...)."
  type        = string
  default     = "docdb5.0"
}

variable "docdb_instance_class" {
  description = "Instance class of the DocumentDB instances."
  type        = string
  default     = "db.t3.medium"
}

variable "docdb_instance_count" {
  description = "Number of DocumentDB instances. One is enough for a test stack, use two or more for failover."
  type        = number
  default     = 1
}

variable "docdb_username" {
  description = "DocumentDB master username. 'admin' and other reserved words are rejected by AWS."
  type        = string
  default     = "kerberos"
}

variable "docdb_password" {
  description = "DocumentDB master password. Leave null to generate one; read it afterwards with 'terraform output -raw docdb_password'."
  type        = string
  default     = null
  sensitive   = true
}

variable "docdb_tls" {
  description = "Enforce TLS (encryption in transit) on the cluster. Keep this enabled; it is the configuration the hub chart's mongodb.tls values are meant for."
  type        = bool
  default     = true
}

variable "docdb_kms_key_id" {
  description = "KMS key ARN for encryption at rest. Leave null to use the AWS managed key."
  type        = string
  default     = null
}

variable "docdb_backup_retention_period" {
  description = "Number of days automated backups are retained."
  type        = number
  default     = 1
}

variable "docdb_deletion_protection" {
  description = "Prevent the cluster from being deleted. Keep false for a throwaway test stack."
  type        = bool
  default     = false
}

variable "docdb_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Keep true for a throwaway test stack."
  type        = bool
  default     = true
}

variable "docdb_enabled_cloudwatch_logs_exports" {
  description = "Log types exported to CloudWatch (audit, profiler)."
  type        = list(string)
  default     = []
}

variable "docdb_allowed_cidrs" {
  description = "Extra CIDR blocks allowed to reach DocumentDB on port 27017, on top of the EKS worker nodes (for example a bastion subnet)."
  type        = list(string)
  default     = []
}
