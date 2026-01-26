# =============================================================================
# Maestro Agent Module - Outputs
# =============================================================================

output "maestro_agent_role_name" {
  description = "IAM role name for Maestro Agent"
  value       = aws_iam_role.maestro_agent.name
}

output "maestro_agent_mqtt_cert_secret_name" {
  description = "Secrets Manager secret name for agent MQTT certificate (for Helm values)"
  value       = data.aws_secretsmanager_secret.maestro_agent_mqtt_cert.name
}

output "maestro_agent_mqtt_cert_secret_arn" {
  description = "Secrets Manager secret ARN for agent MQTT certificate"
  value       = data.aws_secretsmanager_secret.maestro_agent_mqtt_cert.arn
}

output "cluster_id" {
  description = "Management cluster identifier"
  value       = var.cluster_id
}

output "pod_identity_association_id" {
  description = "EKS Pod Identity association ID"
  value       = aws_eks_pod_identity_association.maestro_agent.association_id
}

# Configuration summary for Helm values
output "helm_values" {
  description = "Recommended Helm values for Maestro Agent deployment"
  value = {
    ascp = {
      mqttCertSecretName = data.aws_secretsmanager_secret.maestro_agent_mqtt_cert.name
    }
    maestro = {
      consumerName = var.cluster_id
    }
  }
}
