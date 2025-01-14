output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "n8n_service_ip" {
  description = "External IP of the n8n service"
  value       = module.kubernetes_config.n8n_service_ip
}