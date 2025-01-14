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
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
}

variable "n8n_encryption_key" {
  description = "n8n encryption key"
  type        = string
}

variable "storage_class_zones" {
  description = "List of zones for storage class"
  type        = list(string)
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