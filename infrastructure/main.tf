provider "google" {
  project = var.project_id
  region  = var.region
}

# Get the current project number
data "google_project" "project" {}

 # Enable Required APIs
locals {
  required_apis = [
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com"
  ]
}

resource "google_project_service" "project_services" {
  for_each = toset(local.required_apis)
  project = data.google_project.project.number
  service = each.key
  disable_on_destroy = false
}

# Service Account
## Create a service account for n8n
resource "google_service_account" "n8n_service_account" {
  account_id   = "n8n-service-account"
  display_name = "n8n Service Account"
  project      = var.project_id

  depends_on = [
    google_project_service.project_services
  ]
}

# Database Service
module "cloudsql" {
  source = "./modules/cloudsql"

  project_id     = var.project_id
  region         = var.region
  service_account_email = google_service_account.n8n_service_account.email

  depends_on = [ google_service_account.n8n_service_account ]
}

# N8N Service
## Artifact Registry Repository
resource "google_artifact_registry_repository" "n8n_repository" {
  repository_id = "n8n-images"
  format       = "DOCKER"
  location     = var.region
  description  = "Docker repository for n8n service"

  labels = {
    "app" = "n8n"
  }

  depends_on = [
    google_project_service.project_services
  ]
}

## Bucket for Cloud Run Volume
resource "google_storage_bucket" "n8n_service" {
  name    = "n8n-service"
  location = var.region
}

resource "google_storage_bucket_iam_member" "n8n_bucket_access" {
  bucket = google_storage_bucket.n8n_service.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.n8n_service_account.email}"
}

## Define the docker url
locals {
  docker_url = "${google_artifact_registry_repository.n8n_repository.location}-docker.pkg.dev/${google_artifact_registry_repository.n8n_repository.project}/${google_artifact_registry_repository.n8n_repository.name}"
  depends_on = [google_artifact_registry_repository.n8n_repository]
}

## Docker Build & Push
resource "null_resource" "docker_build_push" {
  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit \
        --config=../cloudbuild.yaml \
        --substitutions=_IMAGE_NAME=${local.docker_url}/n8n:latest \
        ../
    EOT
  }

  depends_on = [google_artifact_registry_repository.n8n_repository]
}

## Cloud Run Deployment
resource "google_cloud_run_v2_service" "n8n_service" {
  name     = "n8n"
  location = var.region
  ingress = "INGRESS_TRAFFIC_ALL"

  scaling {
    min_instance_count = 1
  }

  # Use the service account
  template {
      service_account = google_service_account.n8n_service_account.email
      session_affinity =  true

      volumes {
        name = "persistent-storage"
        gcs {
          bucket = google_storage_bucket.n8n_service.name
          read_only = false
        }
      }

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [
            module.cloudsql.db_instance_connection_name
          ]
        }
      }

      containers {
        image = "${local.docker_url}/n8n:latest"
        ports {
          container_port = 5678
        }

        resources {
          limits = {
            "memory" = "1Gi"
          }
          startup_cpu_boost = true
        }

        volume_mounts {
          name = "persistent-storage"
          mount_path = "/home/node/.n8n"
        }

        volume_mounts {
          name = "cloudsql"
          mount_path = "/cloudsql"
        }

        # Environment Variables
        ## Hostname
        env {
          name  = "N8N_HOST"
          value = "n8n-${data.google_project.project.number}.${var.region}.run.app"
        }

        ## Database Configuration
        env {
          name  = "DB_TYPE"
          value = "postgresdb"
        }
        env {
          name  = "DB_POSTGRESDB_HOST"
          value = "/cloudsql/${module.cloudsql.db_instance_connection_name}"
        }
        env {
          name  = "DB_POSTGRESDB_PORT"
          value = "5432"
        }
        env {
          name  = "DB_POSTGRESDB_DATABASE"
          value = module.cloudsql.db_name
        }
        env {
          name = "DB_POSTGRESDB_USER"
          value_source {
            secret_key_ref {
              secret  = module.cloudsql.db_user_secret_name
              version = "latest"
            }
          }
        }

        env {
          name = "DB_POSTGRESDB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = module.cloudsql.db_password_secret_name
              version = "latest"
            }
          }
        }
      }
  }

  depends_on = [
    google_project_service.project_services,
    module.cloudsql,
    google_storage_bucket_iam_member.n8n_bucket_access,
    google_storage_bucket.n8n_service,
    null_resource.docker_build_push,
  ]
}
