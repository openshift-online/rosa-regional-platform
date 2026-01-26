# Maestro Cross-Account Architecture Diagram

## Complete IAM Role and Account Setup

```mermaid
graph TB
    subgraph "Regional AWS Account (123456789012)"
        subgraph "Regional EKS Cluster (regional-us-east-1)"
            MS[Maestro Server<br/>ServiceAccount]
            ASCP_RC[AWS Secrets Store<br/>CSI Driver]

            MS -->|Pod Identity| MSRole[IAM Role:<br/>regional-us-east-1-maestro-server]
            MS -->|Volume Mount| ASCP_RC
        end

        subgraph "AWS Secrets Manager (Regional Account)"
            SecretDB[(Secret:<br/>regional-us-east-1/maestro/db-credentials)]
            SecretMQTTServer[(Secret:<br/>regional-us-east-1/maestro/server-mqtt-cert)]
        end

        subgraph "AWS IoT Core (Regional Account)"
            IoTThing1[IoT Thing:<br/>regional-us-east-1-maestro-server]
            IoTThing2[IoT Thing:<br/>management-01-maestro-agent]
            IoTBroker[MQTT Broker<br/>Port 8883]

            IoTThing1 -->|publishes to| IoTBroker
            IoTThing2 -->|subscribes to| IoTBroker
        end

        RDS[(RDS PostgreSQL<br/>Maestro State)]

        MSRole -->|GetSecretValue| SecretDB
        MSRole -->|GetSecretValue| SecretMQTTServer
        ASCP_RC -->|Mounts via<br/>Pod Identity| SecretDB
        ASCP_RC -->|Mounts via<br/>Pod Identity| SecretMQTTServer
        MSRole -->|Connect| IoTBroker
        MSRole -->|Read/Write| RDS
    end

    subgraph "Management AWS Account (987654321098)"
        subgraph "Management EKS Cluster (management-01)"
            MA[Maestro Agent<br/>ServiceAccount]
            ASCP_MC[AWS Secrets Store<br/>CSI Driver]

            MA -->|Pod Identity| MARole[IAM Role:<br/>management-01-maestro-agent<br/>SAME ACCOUNT]
            MA -->|Volume Mount| ASCP_MC
        end

        subgraph "AWS Secrets Manager (Management Account)"
            SecretMQTTAgentLocal[(Secret:<br/>management-01/maestro/agent-mqtt-cert<br/>Manually Created)]
        end

        MARole -->|GetSecretValue<br/>Same Account| SecretMQTTAgentLocal
        ASCP_MC -->|Mounts via<br/>Pod Identity| SecretMQTTAgentLocal
        MA -.->|Connect via MQTT Certificate<br/>Cross-Account IAM Permissions| IoTBroker
    end

    style MSRole fill:#e1f5ff
    style MARole fill:#ffe1e1
    style SecretMQTTAgentLocal fill:#fff3cd
    style IoTBroker fill:#d4edda
    style ASCP_RC fill:#e8f4f8
    style ASCP_MC fill:#e8f4f8
```

## IAM Trust Relationships

```mermaid
sequenceDiagram
    participant MC as Management Cluster Pod<br/>(Account 987654321098)
    participant ASCP as ASCP CSI Driver
    participant STS as AWS STS
    participant SM as Secrets Manager<br/>(Account 987654321098)
    participant IoT as IoT Core<br/>(Account 123456789012)

    Note over MC,SM: Pod Identity Same-Account Flow

    MC->>ASCP: Mount secret volume
    ASCP->>STS: AssumeRole(management-01-maestro-agent)<br/>Source Account: 987654321098

    STS->>STS: Verify Pod Identity Token

    Note over STS: Trust Policy allows:<br/>- Service: pods.eks.amazonaws.com<br/>- Same Account Only

    STS-->>ASCP: Temporary credentials for role

    ASCP->>SM: GetSecretValue(management-01/maestro/agent-mqtt-cert)<br/>Same Account

    Note over SM: No resource policy needed:<br/>Same-account IAM permissions apply

    SM-->>ASCP: Return secret (MQTT certificate + key)
    ASCP-->>MC: Mount secret as files

    MC->>IoT: Connect to Regional IoT Core<br/>using IAM permissions and MQTT certificate
    IoT-->>MC: Authenticated MQTT connection (cross-account via IAM)
```

## Secret Flow Architecture

```mermaid
graph LR
    subgraph "Regional Cluster (Regional Account)"
        TF1[Terraform] -->|Creates| IoTCerts[IoT Certificates]
        IoTCerts -->|Stores in| SM1[Secrets Manager<br/>Regional Account<br/>server-mqtt-cert]

        ASCP_RC1[ASCP CSI Driver] -->|Mounts from<br/>Same Account| SM1
        ASCP_RC1 -->|Mounts as| FilesRC[Files in Pod]

        MS1[Maestro Server] -->|Reads| FilesRC
        MS1 -->|Publishes to| MQTT[IoT Core MQTT<br/>Regional Account]
    end

    subgraph "Management Cluster (Management Account)"
        SM2[Secrets Manager<br/>Management Account<br/>agent-mqtt-cert<br/>Manually Created]

        ASCP_MC1[ASCP CSI Driver] -->|Mounts from<br/>Same Account| SM2
        ASCP_MC1 -->|Mounts as| FilesMC[Files in Pod]

        MA1[Maestro Agent] -->|Reads| FilesMC
        MA1 -.->|Subscribes to<br/>Cross-Account IAM| MQTT
    end

    TF1 -.->|Manual Transfer<br/>Certificate Data| SM2

    style SM1 fill:#fff3cd
    style SM2 fill:#fff3cd
    style ASCP_MC1 fill:#ffe1e1
    style ASCP_RC1 fill:#e8f4f8
    style MQTT fill:#d4edda
```

## Key Components

### Regional Account (123456789012)

**IAM Roles:**
- `regional-us-east-1-maestro-server` - Maestro Server access to IoT Core + RDS + Secrets Manager (via ASCP CSI Driver)

**Resources:**
- AWS IoT Core Things, Certificates, and Policies (for server + all agents)
- AWS Secrets Manager secrets (server cert, DB credentials, consumer registrations)
- RDS PostgreSQL database
- EKS cluster running Maestro Server

**Trust Policy (Same-Account):**
```json
{
  "Statement": [{
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
```

**Note:** Agent certificates are created in Regional IoT Core but stored in Management account Secrets Manager via manual transfer.

### Management Account (987654321098)

**IAM Roles:**
- `management-01-maestro-agent` - Created in **Management Account** (same account as cluster)

**Resources:**
- EKS cluster running Maestro Agent
- AWS Secrets Manager secret (manually created with transferred certificate data)
- Pod Identity association (same-account role)

**Pod Identity Association:**
```hcl
# In Management Cluster Terraform
resource "aws_eks_pod_identity_association" "maestro_agent" {
  cluster_name    = "management-01"
  namespace       = "maestro"
  service_account = "maestro-agent"
  role_arn        = "arn:aws:iam::987654321098:role/management-01-maestro-agent"
  # ↑ Role is in SAME account as management cluster
}
```

**Agent IAM Permissions:**
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ],
    "Resource": "arn:aws:secretsmanager:*:987654321098:secret:management-01/maestro/agent-mqtt-cert*"
  }, {
    "Effect": "Allow",
    "Action": [
      "iot:Connect",
      "iot:Subscribe",
      "iot:Receive",
      "iot:Publish"
    ],
    "Resource": [
      "arn:aws:iot:us-east-1:123456789012:client/management-01-*",
      "arn:aws:iot:us-east-1:123456789012:topic/sources/maestro/consumers/management-01/*",
      "arn:aws:iot:us-east-1:123456789012:topicfilter/sources/maestro/consumers/management-01/*"
    ]
  }]
}
```

**Note:** The agent reads secrets from its own account, but has IAM permissions to access IoT Core in the Regional account.

## Authentication Flow Summary

1. **Regional Cluster (Same Account)**
   - Maestro Server uses Pod Identity → assumes regional account role (same account)
   - ASCP CSI Driver mounts secrets from regional account Secrets Manager (same account)
   - Maestro Server reads mounted files → connects to IoT Core (same account)

2. **Management Cluster (Same Account for Secrets, Cross-Account for IoT)**
   - Maestro Agent uses Pod Identity → assumes management account role (same account)
   - ASCP CSI Driver mounts secrets from management account Secrets Manager (same account)
   - Agent reads mounted certificate files → connects to Regional IoT Core (cross-account via IAM permissions)

## Why This Design?

**Centralized Certificate Creation:**
- All IoT certificates created in one place (regional account IoT Core)
- Certificate data manually transferred to management clusters (not automated)

**Security Benefits:**
- Explicit IAM permissions for cross-account IoT access
- Secrets never in Terraform state (manual transfer process)
- Secrets never transmitted over network (mounted via CSI driver from local account)
- Least privilege access (each role has minimal permissions)
- Account sovereignty (each cluster owns its own secrets)

**Operational Simplicity:**
- No cross-account secret access policies needed
- No cross-account IAM trust policies needed
- Each cluster uses standard same-account Pod Identity
- Simple IAM permissions for IoT access (resource-based authorization)
- Clear operational boundaries between regional and management teams
