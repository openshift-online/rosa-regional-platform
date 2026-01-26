# =============================================================================
# Maestro Infrastructure Module - Outputs
#
# These outputs are used by Helm values and ArgoCD applications to configure
# Maestro components
# =============================================================================

# =============================================================================
# AWS IoT Core Outputs
# =============================================================================

output "iot_mqtt_endpoint" {
  description = "AWS IoT Core MQTT endpoint for broker connection"
  value       = data.aws_iot_endpoint.mqtt.endpoint_address
}

output "maestro_server_thing_name" {
  description = "AWS IoT Thing name for Maestro Server"
  value       = aws_iot_thing.maestro_server.name
}

output "maestro_agent_thing_names" {
  description = "Map of management cluster IDs to AWS IoT Thing names"
  value = {
    for idx, cluster_id in var.management_cluster_ids :
    cluster_id => aws_iot_thing.maestro_agent[idx].name
  }
}

# =============================================================================
# RDS Database Outputs
# =============================================================================

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (hostname:port)"
  value       = aws_db_instance.maestro.endpoint
}

output "rds_address" {
  description = "RDS PostgreSQL hostname"
  value       = aws_db_instance.maestro.address
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.maestro.port
}

output "rds_database_name" {
  description = "Name of the PostgreSQL database"
  value       = aws_db_instance.maestro.db_name
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.maestro.id
}

# =============================================================================
# Secrets Manager Outputs
# =============================================================================

output "maestro_server_mqtt_cert_secret_arn" {
  description = "ARN of Secrets Manager secret containing Maestro Server MQTT certificate"
  value       = aws_secretsmanager_secret.maestro_server_mqtt_cert.arn
}

output "maestro_server_mqtt_cert_secret_name" {
  description = "Name of Secrets Manager secret containing Maestro Server MQTT certificate"
  value       = aws_secretsmanager_secret.maestro_server_mqtt_cert.name
}

output "maestro_db_credentials_secret_arn" {
  description = "ARN of Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.maestro_db_credentials.arn
}

output "maestro_db_credentials_secret_name" {
  description = "Name of Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.maestro_db_credentials.name
}

output "maestro_consumers_secret_arn" {
  description = "ARN of Secrets Manager secret containing pre-provisioned consumer registrations"
  value       = aws_secretsmanager_secret.maestro_consumers.arn
}

output "maestro_consumers_secret_name" {
  description = "Name of Secrets Manager secret containing pre-provisioned consumer registrations"
  value       = aws_secretsmanager_secret.maestro_consumers.name
}

# =============================================================================
# Agent Certificate Data Outputs (SENSITIVE - For Manual Transfer)
# =============================================================================

output "maestro_agent_certificates" {
  description = "Map of management cluster IDs to MQTT certificate data for manual transfer to management clusters (SENSITIVE)"
  sensitive   = true
  value = {
    for idx, cluster_id in var.management_cluster_ids :
    cluster_id => {
      certificate   = aws_iot_certificate.maestro_agent[idx].certificate_pem
      privateKey    = aws_iot_certificate.maestro_agent[idx].private_key
      caCert        = data.http.aws_iot_root_ca.response_body
      endpoint      = data.aws_iot_endpoint.mqtt.endpoint_address
      port          = "8883"
      clientId      = "${cluster_id}-maestro-agent"
      consumerName  = cluster_id
    }
  }
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "maestro_server_role_arn" {
  description = "ARN of IAM role for Maestro Server (Pod Identity)"
  value       = aws_iam_role.maestro_server.arn
}

output "maestro_server_role_name" {
  description = "Name of IAM role for Maestro Server"
  value       = aws_iam_role.maestro_server.name
}

# Agent IAM roles are now created in management cluster Terraform
# See terraform/config/management-cluster/ for agent role outputs

# =============================================================================
# Configuration Summary (for easy reference)
# =============================================================================

output "maestro_configuration_summary" {
  description = "Summary of Maestro infrastructure configuration for Helm values"
  value = {
    mqtt = {
      endpoint    = data.aws_iot_endpoint.mqtt.endpoint_address
      port        = 8883
      topicPrefix = var.mqtt_topic_prefix
    }
    database = {
      host = aws_db_instance.maestro.address
      port = aws_db_instance.maestro.port
      name = aws_db_instance.maestro.db_name
    }
    server = {
      roleArn        = aws_iam_role.maestro_server.arn
      mqttSecretName = aws_secretsmanager_secret.maestro_server_mqtt_cert.name
      dbSecretName   = aws_secretsmanager_secret.maestro_db_credentials.name
    }
    # Agent configuration moved to management cluster Terraform
    # Certificate data available in maestro_agent_certificates output (sensitive)
  }
}
