provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable Required APIs
resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"
}

resource "google_project_service" "cloud_build" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com" # Required for IAM and networking
}

# Artifact Registry
resource "google_artifact_registry_repository" "n8n_repository" {
  repository_id = "n8n-images"
  format       = "DOCKER"
  location     = var.region
  description  = "Docker repository for n8n service"

  labels = {
    "app" = "n8n"
  }

  depends_on = [
    google_project_service.artifact_registry
  ]
}

# Define the docker url
locals {
  docker_url = "${google_artifact_registry_repository.n8n_repository.location}-docker.pkg.dev/${google_artifact_registry_repository.n8n_repository.project}/${google_artifact_registry_repository.n8n_repository.name}"
  depends_on = [google_artifact_registry_repository.n8n_repository]
}

# Docker Build & Push
resource "null_resource" "docker_build_push" {
  provisioner "local-exec" {
    command = <<EOT
      docker build  --platform linux/amd64 --push -t ${local.docker_url}/n8n:latest ../
    EOT
  }
  depends_on = [google_artifact_registry_repository.n8n_repository]
}

# Cloud Run Deployment
resource "google_cloud_run_service" "n8n_service" {
  name     = "n8n"
  location = var.region

  template {
    spec {
      containers {
        image = "${local.docker_url}/n8n:latest"
        ports {
          container_port = 5678
        }
      }
    }
  }

  autogenerate_revision_name = true

  depends_on = [
    google_project_service.cloud_run,
    google_project_service.compute,
    null_resource.docker_build_push
  ]
}

# Optional IAM Binding for Public Access (Adjust as Needed)
# resource "google_cloud_run_service_iam_binding" "n8n_public" {
#   service    = google_cloud_run_service.n8n_service.name
#   location   = var.region
#   role       = "roles/run.invoker"
#   members    = ["allUsers"] # Allows public access; modify this for restricted access

#   depends_on = [google_cloud_run_service.n8n_service]
# }

# Create a group for n8n users
# resource "google_cloud_identity_group" "n8n_users_group" {
#   parent      = "customers/${data.google_client_config.current.project_number}"
#   display_name = "n8n-users"
#   labels = {
#     "app" = "n8n"
#   }

#   group_key {
#     id = "n8n-users@${google_project_service.cloud_run.project}.iam.gserviceaccount.com"
#   }
# }

# # Grant IAP access to the group
# resource "google_iap_web_iam_member" "iap_access" {
#   project       = var.project_id
#   role          = "roles/iap.httpsResourceAccessor"
#   member        = "group:${google_cloud_identity_group.n8n_users_group.group_key.id}"
#   depends_on = [google_cloud_identity_group.n8n_users_group, google_cloud_run_service.n8n_service]
# }