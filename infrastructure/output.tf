output "cloud_run_url" {
  value       = google_cloud_run_service.n8n_service.status[0].url
  description = "The URL of the deployed Cloud Run service for n8n."
}