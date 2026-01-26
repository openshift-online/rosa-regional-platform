# =============================================================================
# AWS Secrets Manager Resources
#
# Stores MQTT certificates and database credentials for Maestro components
# These secrets are synced to Kubernetes via External Secrets Operator
# =============================================================================

# =============================================================================
# Maestro Server Secrets
# =============================================================================

# MQTT Certificate and Private Key for Maestro Server
resource "aws_secretsmanager_secret" "maestro_server_mqtt_cert" {
  name        = "${var.resource_name_base}/maestro/server-mqtt-cert"
  description = "MQTT client certificate and private key for Maestro Server"

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-server-mqtt-cert"
      Component = "maestro-server"
    }
  )
}

resource "aws_secretsmanager_secret_version" "maestro_server_mqtt_cert" {
  secret_id = aws_secretsmanager_secret.maestro_server_mqtt_cert.id

  secret_string = jsonencode({
    certificate = aws_iot_certificate.maestro_server.certificate_pem
    privateKey  = aws_iot_certificate.maestro_server.private_key
    caCert      = data.http.aws_iot_root_ca.response_body
    endpoint    = data.aws_iot_endpoint.mqtt.endpoint_address
    port        = "8883"
    clientId    = "${var.resource_name_base}-maestro-server"
  })
}

# Database Credentials for Maestro Server
resource "aws_secretsmanager_secret" "maestro_db_credentials" {
  name        = "${var.resource_name_base}/maestro/db-credentials"
  description = "PostgreSQL database credentials for Maestro Server"

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-db-credentials"
      Component = "maestro-server"
    }
  )
}

resource "aws_secretsmanager_secret_version" "maestro_db_credentials" {
  secret_id = aws_secretsmanager_secret.maestro_db_credentials.id

  secret_string = jsonencode({
    username = aws_db_instance.maestro.username
    password = random_password.db_password.result
    host     = aws_db_instance.maestro.address
    port     = tostring(aws_db_instance.maestro.port)
    database = aws_db_instance.maestro.db_name
  })
}

# =============================================================================
# Maestro Agent Secrets - MANUAL TRANSFER
# =============================================================================
#
# Agent MQTT certificates are NOT stored in regional account Secrets Manager.
# Instead, they are output as sensitive Terraform outputs for manual transfer.
#
# Process:
# 1. Regional operator runs: terraform output -json maestro_agent_certificates
# 2. Regional operator securely transfers certificate data to management cluster operator
# 3. Management cluster operator creates secret in their own Secrets Manager
# 4. Management cluster Terraform references the secret name
#
# See outputs.tf for the certificate data outputs.
#
# =============================================================================
# Consumer Pre-Registration Data
# =============================================================================

# Store consumer registration information for pre-provisioning
# This allows agents to connect without needing to call registration API
resource "aws_secretsmanager_secret" "maestro_consumers" {
  name        = "${var.resource_name_base}/maestro/consumers"
  description = "Pre-provisioned consumer registrations for Maestro"

  tags = merge(
    local.common_tags,
    {
      Name      = "${var.resource_name_base}-maestro-consumers"
      Component = "maestro-server"
    }
  )
}

resource "aws_secretsmanager_secret_version" "maestro_consumers" {
  secret_id = aws_secretsmanager_secret.maestro_consumers.id

  secret_string = jsonencode({
    consumers = [
      for idx, cluster_id in var.management_cluster_ids : {
        name = cluster_id
        labels = {
          cluster_type = "management"
          region       = data.aws_region.current.id
          cluster_id   = cluster_id
        }
      }
    ]
  })
}
