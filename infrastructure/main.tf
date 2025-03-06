provider "google" {
  project = var.project_id
  region  = var.region
}

# Get the current project number
data "google_project" "project" {}

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

resource "google_project_service" "cloud_sql" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
}

resource "google_project_service" "secret_manager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"
}

# Service Account
## Create a service account for n8n
resource "google_service_account" "n8n_service_account" {
  account_id   = "n8n-service-account"
  display_name = "n8n Service Account"
  project      = var.project_id

  depends_on = [
    google_project_service.cloud_run,
    google_project_service.cloud_sql
  ]
}

## IAM Binding for Cloud SQL Client Role
resource "google_project_iam_member" "n8n_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.n8n_service_account.email}"

  depends_on = [google_service_account.n8n_service_account]
}

# PostgreSQL
## PostgreSQL Instance
resource "google_sql_database_instance" "n8n_instance" {
  name             = "n8n-db"
  database_version = "POSTGRES_13"
  region           = var.region
  project          = var.project_id
  settings {
    tier = "db-f1-micro"
  }

  depends_on = [
    google_project_service.cloud_sql,
    google_project_service.compute
  ]
}

## PostgreSQL Database
resource "google_sql_database" "n8n_db" {
  name     = "n8n"
  instance = google_sql_database_instance.n8n_instance.name

  depends_on = [google_sql_database_instance.n8n_instance]
}

## Random Password
resource "random_password" "n8n_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

## PostgreSQL User
resource "google_sql_user" "n8n_user" {
  name     = "n8n"
  instance = google_sql_database_instance.n8n_instance.name
  password = random_password.n8n_password.result
  depends_on = [google_sql_database_instance.n8n_instance]
}

## PostgreSQL User Secrets
resource "google_secret_manager_secret" "n8n_db_user" {
  secret_id = "n8n_db_user"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "n8n_db_user" {
  secret      = google_secret_manager_secret.n8n_db_user.id
  secret_data = google_sql_user.n8n_user.name

  depends_on = [
    google_secret_manager_secret.n8n_db_user
  ]
}

resource "google_secret_manager_secret_iam_member" "n8n_secret_accessor_sql_user" {
  project = var.project_id
  secret_id = google_secret_manager_secret.n8n_db_user.secret_id
  role = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.n8n_service_account.email}"

  depends_on = [google_secret_manager_secret.n8n_db_user]
}

resource "google_secret_manager_secret" "n8n_db_password" {
  secret_id = "n8n_db_password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "n8n_db_password" {
  secret      = google_secret_manager_secret.n8n_db_password.id
  secret_data = random_password.n8n_password.result

  depends_on = [
    random_password.n8n_password,
    google_secret_manager_secret.n8n_db_password
  ]
}

resource "google_secret_manager_secret_iam_member" "n8n_secret_accessor_sql_password" {
  project = var.project_id
  secret_id = google_secret_manager_secret.n8n_db_password.secret_id
  role = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.n8n_service_account.email}"

  depends_on = [google_secret_manager_secret.n8n_db_password]
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
    google_project_service.artifact_registry
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
            google_sql_database_instance.n8n_instance.connection_name
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
          value = "/cloudsql/${google_sql_database_instance.n8n_instance.connection_name}"
        }
        env {
          name  = "DB_POSTGRESDB_PORT"
          value = "5432"
        }
        env {
          name  = "DB_POSTGRESDB_DATABASE"
          value = google_sql_database.n8n_db.name
        }
        env {
          name = "DB_POSTGRESDB_USER"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.n8n_db_user.name
              version = "latest"
            }
          }
        }

        env {
          name = "DB_POSTGRESDB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.n8n_db_password.name
              version = "latest"
            }
          }
        }
      }
  }

  depends_on = [
    google_project_service.cloud_run,
    google_project_service.compute,
    google_project_iam_member.n8n_sql_client,
    google_storage_bucket_iam_member.n8n_bucket_access,
    google_storage_bucket.n8n_service,
    null_resource.docker_build_push,
    google_sql_database_instance.n8n_instance,
    google_sql_database.n8n_db,
    google_sql_user.n8n_user,
    google_secret_manager_secret.n8n_db_user,
    google_secret_manager_secret.n8n_db_password,
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