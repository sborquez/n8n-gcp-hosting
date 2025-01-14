variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = "default"
}

variable "node_locations" {
  description = "List of zones for node pool"
  type        = list(string)
  default     = ["us-central1-b", "us-central1-c"]
}

# variable "n8n_hostname" {
#   description = "Hostname for n8n service"
#   type        = string
# }

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "n8n"
}

variable "n8n_encryption_key" {
  description = "n8n encryption key"
  type        = string
  sensitive   = true
}

variable "postgres_non_root_user" {
  description = "PostgreSQL non-root username"
  type        = string
  default     = ""  # Will default to postgres_user if not set
}

variable "postgres_non_root_password" {
  description = "PostgreSQL non-root password"
  type        = string
  default     = ""  # Will default to postgres_password if not set
  sensitive   = true
}