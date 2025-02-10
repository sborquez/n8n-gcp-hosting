output "cloud_run_url" {
  value       = google_cloud_run_v2_service.n8n_service.urls[0]
  description = "The URL of the deployed Cloud Run service for n8n."
}

output "n8n_service_account" {
  value       = google_service_account.n8n_service_account.email
  description = "The email address of the service account used by the n8n Cloud Run service."
}

# output "n8n_sql_password" {
#   value       = google_sql_user.n8n_user.password
#   description = "The password for the n8n user in the Cloud SQL database."
# }