# Get the current project number
data "google_project" "project" {}

 # Enable Required APIs
locals {
  required_apis = [
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com"
  ]
}

resource "google_project_service" "project_services_cloudsql" {
  for_each = toset(local.required_apis)
  project = data.google_project.project.number
  service = each.key
  disable_on_destroy = false
}

## IAM Binding for Cloud SQL Client Role
resource "google_project_iam_member" "n8n_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [
    google_project_service.project_services_cloudsql
  ]
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
    google_project_service.project_services_cloudsql
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

## Cloud SQL User
resource "google_sql_user" "n8n_user" {
  name     = "n8n"
  instance = google_sql_database_instance.n8n_instance.name
  password = random_password.n8n_password.result
  depends_on = [google_sql_database_instance.n8n_instance]
}

## Cloud SQL User Secrets
resource "google_secret_manager_secret" "n8n_db_user" {
  secret_id = "n8n_db_user"
  replication {
    auto {}
  }

  depends_on = [ google_project_service.project_services_cloudsql ]
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
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [google_secret_manager_secret.n8n_db_user]
}

resource "google_secret_manager_secret" "n8n_db_password" {
  secret_id = "n8n_db_password"
  replication {
    auto {}
  }
  depends_on = [ google_project_service.project_services_cloudsql ]
}

## Cloud SQL Password Secrets
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
  member  = "serviceAccount:${var.service_account_email}"

  depends_on = [google_secret_manager_secret.n8n_db_password]
}
