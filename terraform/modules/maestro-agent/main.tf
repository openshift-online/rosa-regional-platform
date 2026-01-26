# =============================================================================
# Maestro Agent Module - Main Configuration
# =============================================================================

# Get current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Default secret name if not provided
locals {
  mqtt_cert_secret_name = var.mqtt_cert_secret_name != "" ? var.mqtt_cert_secret_name : "${var.cluster_id}/maestro/agent-mqtt-cert"

  common_tags = merge(
    var.tags,
    {
      Component         = "maestro-agent"
      ManagementCluster = var.cluster_id
      ManagedBy         = "terraform"
    }
  )
}

# Reference existing MQTT certificate secret (created manually via AWS CLI)
data "aws_secretsmanager_secret" "maestro_agent_mqtt_cert" {
  name = local.mqtt_cert_secret_name
}
