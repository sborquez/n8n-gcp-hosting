terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "container" {
  service = "container.googleapis.com"
  disable_dependent_services = true
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
  disable_dependent_services = true
}

resource "google_project_service" "cloudresourcemanager" {
  service = "cloudresourcemanager.googleapis.com"
  disable_dependent_services = true
}

module "gke" {
  source = "./modules/gke"

  depends_on = [
    google_project_service.container,
    google_project_service.compute,
    google_project_service.cloudresourcemanager
  ]

  project_id    = var.project_id
  region        = var.region
  cluster_name  = var.cluster_name
  node_count    = var.node_count
  machine_type  = var.machine_type
  network       = var.network
  subnetwork    = var.subnetwork
  node_locations = var.node_locations
}

module "kubernetes_config" {
  source = "./modules/kubernetes"

  depends_on = [module.gke]

  # n8n_hostname       = var.n8n_hostname
  postgres_user      = var.postgres_user
  postgres_password  = var.postgres_password
  postgres_non_root_user = var.postgres_non_root_user
  postgres_non_root_password = var.postgres_non_root_password
  postgres_db        = var.postgres_db
  n8n_encryption_key = var.n8n_encryption_key
  storage_class_zones = var.node_locations
}
