# outputs.tf

output "db_instance_connection_name" {
  value       = "${var.project_id}:${var.region}:n8n-db"
  description = "Connection name for the N8N DB (formatted to match CloudSQL connection string)"
}

output "db_name" {
  value       = "n8n"
  description = "The N8N DB name"
}

output "db_user_secret_name" {
  value       = google_secret_manager_secret.n8n_db_user.name
  description = "The DB user secret name for the new instance"
}

output "db_password_secret_name" {
  value       = google_secret_manager_secret.n8n_db_password.name
  description = "The DB password secret name for the new instance"
}

output "postgres_vm_internal_ip" {
  value       = google_compute_instance.n8n_instance.network_interface[0].network_ip
  description = "The internal IP address of the PostgreSQL VM"
}