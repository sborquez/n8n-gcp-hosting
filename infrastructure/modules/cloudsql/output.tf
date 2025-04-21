output "db_instance_connection_name" {
  value       = google_sql_database_instance.n8n_instance.connection_name
  description = "Connection name for the N8N DB"
}

output "db_name" {
  value       = google_sql_database.n8n_db.name
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