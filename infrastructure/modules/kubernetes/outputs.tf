output "n8n_service_ip" {
  description = "External IP of the n8n service"
  value       = kubernetes_service.n8n.status[0].load_balancer[0].ingress[0].ip
}