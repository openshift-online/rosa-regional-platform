# Maestro Architecture Overview

This document provides comprehensive architecture diagrams for the Maestro MQTT-based orchestration system in the ROSA Regional Platform.

## Table of Contents
1. [High-Level Architecture](#high-level-architecture)
2. [Complete Message Flow](#complete-message-flow)
3. [MQTT Topic Structure](#mqtt-topic-structure)
4. [IAM Roles and Cross-Account Setup](#iam-roles-and-cross-account-setup)
5. [Deployment Workflow](#deployment-workflow)
6. [Certificate Transfer Process](#certificate-transfer-process)
7. [Network Topology](#network-topology)

---

## High-Level Architecture

This diagram shows all AWS components and their relationships across Regional and Management clusters.

```mermaid
graph TB
    subgraph Regional["Regional AWS Account (123456789012)"]
        subgraph RegVPC["VPC: 10.0.0.0/16"]
            subgraph RegEKS["EKS Cluster: regional-us-east-1"]
                Server["Maestro Server<br/>───────────<br/>Replicas: 2<br/>Ports: 8080(HTTP), 8090(gRPC)<br/>ServiceAccount: maestro-server"]
                ASCP_S["AWS Secrets Store<br/>CSI Driver<br/>Mount: /mnt/secrets-store"]

                Server -->|Mounts| ASCP_S
            end

            subgraph DBSubnet["Private Subnets (Multi-AZ)"]
                RDS["RDS PostgreSQL 16.4<br/>───────────<br/>Instance: db.t4g.micro<br/>Storage: 20GB (encrypted)<br/>Backups: 7 days"]
            end

            SG_DB["Security Group<br/>Port 5432<br/>Source: EKS cluster only"]
        end

        IoT["AWS IoT Core<br/>───────────<br/>Endpoint: *.iot.us-east-1.amazonaws.com:8883<br/>Auth: X.509 Certificates<br/>Protocol: MQTT TLS"]

        subgraph SM_Reg["AWS Secrets Manager"]
            SM_Server["regional-us-east-1/maestro/<br/>server-mqtt-cert<br/>(cert + key)"]
            SM_DB["regional-us-east-1/maestro/<br/>db-credentials<br/>(host, port, user, pass)"]
            SM_Consumers["regional-us-east-1/maestro/<br/>consumers<br/>(pre-provisioned metadata)"]
        end

        IAM_Server["IAM Role<br/>regional-us-east-1-maestro-server<br/>───────────<br/>Permissions:<br/>• IoT: Connect, Publish, Subscribe<br/>• RDS: Connect<br/>• Secrets: GetSecretValue"]

        Server -->|Pod Identity| IAM_Server
        IAM_Server -->|Read| SM_Server
        IAM_Server -->|Read| SM_DB
        IAM_Server -->|Read| SM_Consumers
        ASCP_S -.->|Mounts as files| SM_Server
        ASCP_S -.->|Mounts as files| SM_DB
        Server -->|Port 5432<br/>SSL/TLS| SG_DB
        SG_DB -->|Access| RDS
        Server -->|MQTT<br/>Port 8883| IoT
    end

    subgraph Mgmt1["Management AWS Account (987654321098)"]
        subgraph MgmtVPC1["VPC: 10.1.0.0/16"]
            subgraph MgmtEKS1["EKS Cluster: management-01"]
                Agent1["Maestro Agent<br/>───────────<br/>Replicas: 1<br/>Consumer: management-01<br/>ServiceAccount: maestro-agent"]
                ASCP_A1["AWS Secrets Store<br/>CSI Driver<br/>Mount: /mnt/secrets-store"]

                Agent1 -->|Mounts| ASCP_A1
            end
        end

        SM_Agent1["AWS Secrets Manager<br/>management-01/maestro/<br/>agent-mqtt-cert<br/>(manually created)"]

        IAM_Agent1["IAM Role<br/>management-01-maestro-agent<br/>───────────<br/>Permissions:<br/>• IoT: Connect to Regional IoT (cross-account)<br/>• Secrets: GetSecretValue (local)<br/>Trust: pods.eks.amazonaws.com (same account)"]

        Agent1 -->|Pod Identity<br/>Same Account| IAM_Agent1
        IAM_Agent1 -->|Read<br/>Local Secret| SM_Agent1
        ASCP_A1 -.->|Mounts as files| SM_Agent1
        Agent1 -.->|MQTT<br/>Port 8883<br/>Cross-Account IAM| IoT
    end

    subgraph Mgmt2["Management AWS Account (234567890123)"]
        subgraph MgmtVPC2["VPC: 10.2.0.0/16"]
            subgraph MgmtEKS2["EKS Cluster: management-02"]
                Agent2["Maestro Agent<br/>───────────<br/>Replicas: 1<br/>Consumer: management-02<br/>ServiceAccount: maestro-agent"]
                ASCP_A2["AWS Secrets Store<br/>CSI Driver"]

                Agent2 -->|Mounts| ASCP_A2
            end
        end

        SM_Agent2["AWS Secrets Manager<br/>management-02/maestro/<br/>agent-mqtt-cert<br/>(manually created)"]

        IAM_Agent2["IAM Role<br/>management-02-maestro-agent<br/>───────────<br/>Trust: pods.eks.amazonaws.com (same account)"]

        Agent2 -->|Pod Identity<br/>Same Account| IAM_Agent2
        IAM_Agent2 -->|Read<br/>Local Secret| SM_Agent2
        ASCP_A2 -.->|Mounts as files| SM_Agent2
        Agent2 -.->|MQTT<br/>Port 8883<br/>Cross-Account IAM| IoT
    end

    style Server fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style Agent1 fill:#ffe1e1,stroke:#cc0000,stroke-width:2px
    style Agent2 fill:#ffe1e1,stroke:#cc0000,stroke-width:2px
    style IoT fill:#d4edda,stroke:#28a745,stroke-width:3px
    style RDS fill:#e8e8ff,stroke:#6666ff,stroke-width:2px
    style SM_Server fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    style SM_DB fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    style IAM_Server fill:#cce5ff
    style IAM_Agent1 fill:#ffcccc
    style IAM_Agent2 fill:#ffcccc
```

**Key Points:**
- **Regional Cluster**: Centralized Maestro Server with RDS state database
- **Management Clusters**: Distributed agents in separate AWS accounts
- **AWS IoT Core**: MQTT broker enabling pub/sub communication (cross-account via IAM permissions)
- **Same-Account Pod Identity**: Each cluster uses Pod Identity with roles in their own account
- **Local Secrets**: Each cluster reads MQTT certificates from its own Secrets Manager
- **Network Isolation**: No direct network path between regional and management clusters

---

## Complete Message Flow

End-to-end flow showing how ManifestWork resources are distributed from Regional to Management clusters.

```mermaid
sequenceDiagram
    participant User as Platform Operator
    participant API as Regional Cluster<br/>Maestro HTTP API
    participant Server as Maestro Server<br/>(Regional)
    participant DB as RDS PostgreSQL<br/>(Regional)
    participant SM as Secrets Manager<br/>(Regional)
    participant IoT as AWS IoT Core<br/>MQTT Broker
    participant Agent as Maestro Agent<br/>(Management)
    participant K8s as Management Cluster<br/>Kubernetes API

    Note over User,K8s: Initialization Phase
    Server->>SM: Read server MQTT cert via ASCP (local)
    Server->>DB: Initialize schema, load consumers
    Server->>IoT: Connect with X.509 cert
    Note over Agent: Agent reads from Management account Secrets Manager
    Agent->>Agent: Read agent MQTT cert via ASCP (local)
    Agent->>IoT: Connect with X.509 cert (cross-account via IAM)
    Agent->>IoT: Subscribe to topic:<br/>sources/maestro/consumers/management-01/sourceevents

    Note over User,K8s: ManifestWork Creation
    User->>API: POST /api/maestro/v1/resources<br/>ManifestWork manifest
    API->>Server: Create ManifestWork
    Server->>DB: Store ManifestWork (status: pending)
    DB-->>Server: Stored (ID: abc123)
    Server->>Server: Wrap in CloudEvent envelope
    Server->>IoT: Publish to topic:<br/>sources/maestro/consumers/management-01/sourceevents

    Note over User,K8s: Message Delivery
    IoT->>Agent: Deliver MQTT message
    Agent->>Agent: Parse CloudEvent
    Agent->>Agent: Extract ManifestWork payload
    Agent->>K8s: Apply Kubernetes resources<br/>(Deployment, Service, etc.)
    K8s-->>Agent: Resources created
    Agent->>Agent: Create AppliedManifestWork<br/>(status: Applied)

    Note over User,K8s: Status Reporting
    Agent->>Agent: Wrap status in CloudEvent
    Agent->>IoT: Publish to topic:<br/>sources/maestro/consumers/management-01/agentevents
    IoT->>Server: Deliver status message
    Server->>Server: Parse status CloudEvent
    Server->>DB: Update ManifestWork<br/>(status: Applied)

    Note over User,K8s: Status Query
    User->>API: GET /api/maestro/v1/resources/abc123
    API->>Server: Get ManifestWork status
    Server->>DB: Query status
    DB-->>Server: status: Applied
    Server-->>API: Return status
    API-->>User: HTTP 200 OK<br/>status: Applied

    Note over User,K8s: Health Monitoring
    Agent->>K8s: Watch applied resources
    K8s-->>Agent: Resource health events
    Agent->>IoT: Publish status updates<br/>(periodic heartbeat)
    IoT->>Server: Deliver updates
    Server->>DB: Update resource status
```

**Message Flow Steps:**
1. **Initialization**: Server and agents connect to IoT Core with X.509 certificates
2. **Subscription**: Agents subscribe to their consumer-specific topics
3. **Publication**: Server publishes ManifestWork wrapped in CloudEvent to agent topic
4. **Application**: Agent receives, parses, and applies Kubernetes resources
5. **Status Update**: Agent reports status back through separate MQTT topic
6. **Persistence**: Server stores all state in RDS for API queries

---

## MQTT Topic Structure

Hierarchical topic organization for consumer isolation and message routing.

```mermaid
graph TB
    Root["MQTT Topic Root<br/>sources/maestro/consumers"]

    Root --> C1["/{consumer-name-1}"]
    Root --> C2["/{consumer-name-2}"]
    Root --> CN["/{consumer-name-N}"]

    C1 --> SE1["sourceevents<br/>───────────<br/>Direction: Server → Agent<br/>Publisher: Maestro Server<br/>Subscriber: Maestro Agent<br/>QoS: 1 (at least once)<br/>Payload: CloudEvent + ManifestWork"]

    C1 --> AE1["agentevents<br/>───────────<br/>Direction: Agent → Server<br/>Publisher: Maestro Agent<br/>Subscriber: Maestro Server<br/>QoS: 1 (at least once)<br/>Payload: CloudEvent + Status"]

    C2 --> SE2["sourceevents"]
    C2 --> AE2["agentevents"]

    CN --> SEN["sourceevents"]
    CN --> AEN["agentevents"]

    style Root fill:#d4edda,stroke:#28a745,stroke-width:3px
    style SE1 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style AE1 fill:#ffe1e1,stroke:#cc0000,stroke-width:2px
    style SE2 fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style AE2 fill:#ffe1e1,stroke:#cc0000,stroke-width:2px
    style SEN fill:#e1f5ff,stroke:#0066cc,stroke-width:2px
    style AEN fill:#ffe1e1,stroke:#cc0000,stroke-width:2px
```

**Topic Examples:**
- **Server publishes to**: `sources/maestro/consumers/management-01/sourceevents`
- **Agent subscribes to**: `sources/maestro/consumers/management-01/sourceevents`
- **Agent publishes to**: `sources/maestro/consumers/management-01/agentevents`
- **Server subscribes to**: `sources/maestro/consumers/+/agentevents` (wildcard)

**Security:**
- Each agent has IoT Policy allowing subscribe/receive ONLY on its consumer-specific topic
- Server has IoT Policy allowing publish to all `sourceevents` topics
- Topic isolation ensures multi-tenant security

---

## IAM Roles and Cross-Account Setup

Detailed IAM role configuration, Pod Identity associations, and cross-account authentication flows.

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

### IAM Trust Relationships

Detailed flow showing how Pod Identity enables same-account secret access and cross-account IoT authentication.

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

### Secret Flow Architecture

Shows how secrets flow from Terraform creation through manual transfer to pod consumption.

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

### Key Components

#### Regional Account (123456789012)

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

#### Management Account (987654321098)

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

### Authentication Flow Summary

1. **Regional Cluster (Same Account)**
   - Maestro Server uses Pod Identity → assumes regional account role (same account)
   - ASCP CSI Driver mounts secrets from regional account Secrets Manager (same account)
   - Maestro Server reads mounted files → connects to IoT Core (same account)

2. **Management Cluster (Same Account for Secrets, Cross-Account for IoT)**
   - Maestro Agent uses Pod Identity → assumes management account role (same account)
   - ASCP CSI Driver mounts secrets from management account Secrets Manager (same account)
   - Agent reads mounted certificate files → connects to Regional IoT Core (cross-account via IAM permissions)

### Why This Design?

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

---

## Deployment Workflow

Complete deployment sequence showing manual certificate transfer between accounts.

```mermaid
sequenceDiagram
    participant RegOp as Regional<br/>Operator
    participant RegTF as Regional<br/>Terraform
    participant AWS_R as Regional<br/>AWS Account
    participant Transfer as Secure<br/>Transfer Channel
    participant MgmtOp as Management<br/>Operator
    participant MgmtCLI as AWS CLI<br/>(Management)
    participant MgmtTF as Management<br/>Terraform
    participant AWS_M as Management<br/>AWS Account

    Note over RegOp,AWS_M: Phase 1: Regional Infrastructure
    RegOp->>RegTF: terraform apply<br/>maestro-infrastructure
    RegTF->>AWS_R: Create IoT Things + Certs
    RegTF->>AWS_R: Create RDS PostgreSQL
    RegTF->>AWS_R: Create Secrets Manager secrets
    RegTF->>AWS_R: Create Server IAM role + Pod Identity
    AWS_R-->>RegTF: Resources created
    RegTF-->>RegOp: Apply complete

    Note over RegOp,AWS_M: Phase 2: Certificate Extraction
    RegOp->>RegTF: terraform output -json<br/>maestro_agent_certificates
    RegTF-->>RegOp: {"management-01": {<br/>"certificateArn": "...",<br/>"certificatePem": "...",<br/>"privateKey": "...",<br/>"endpoint": "..."}}
    RegOp->>RegOp: jq '.["management-01"]' > cert.json
    RegOp->>RegOp: Encrypt cert.json

    Note over RegOp,AWS_M: Phase 3: Secure Transfer
    RegOp->>Transfer: Transfer encrypted cert.json<br/>(GPG / AWS Secrets Manager /<br/>HashiCorp Vault / etc.)
    Transfer->>MgmtOp: Receive encrypted file
    MgmtOp->>MgmtOp: Decrypt cert.json

    Note over RegOp,AWS_M: Phase 4: Management Cluster Secret
    MgmtOp->>MgmtCLI: aws secretsmanager create-secret<br/>--name management-01/maestro/agent-mqtt-cert<br/>--secret-string file://cert.json
    MgmtCLI->>AWS_M: Create secret in Secrets Manager
    AWS_M-->>MgmtCLI: Secret created
    MgmtOp->>MgmtOp: shred -u cert.json

    Note over RegOp,AWS_M: Phase 5: Management Cluster IAM
    MgmtOp->>MgmtTF: terraform apply<br/>maestro-agent
    MgmtTF->>AWS_M: Create Agent IAM role (same account)
    MgmtTF->>AWS_M: Add IoT permissions (to Regional IoT)
    MgmtTF->>AWS_M: Create Pod Identity association
    AWS_M-->>MgmtTF: Resources created
    MgmtTF-->>MgmtOp: Apply complete

    Note over RegOp,AWS_M: Phase 6: Helm Deployments
    RegOp->>RegTF: terraform output<br/>maestro_configuration_summary
    RegTF-->>RegOp: Helm values (role ARN, secrets, endpoint)
    RegOp->>AWS_R: helm install maestro-server<br/>--set aws.podIdentity.roleArn=...<br/>--set ascp.mqttCertSecretName=...
    AWS_R-->>RegOp: Server deployed

    MgmtOp->>MgmtTF: terraform output helm_values
    MgmtTF-->>MgmtOp: Helm values
    MgmtOp->>AWS_M: helm install maestro-agent<br/>--set maestro.consumerName=management-01<br/>--set broker.endpoint=...
    AWS_M-->>MgmtOp: Agent deployed

    Note over RegOp,AWS_M: Phase 7: Verification
    RegOp->>AWS_R: kubectl logs maestro-server
    AWS_R-->>RegOp: Connected to IoT Core ✓<br/>DB connection established ✓
    MgmtOp->>AWS_M: kubectl logs maestro-agent
    AWS_M-->>MgmtOp: Connected to IoT Core ✓<br/>Subscribed to topic ✓
```

**Why Manual Transfer?**
- Keeps sensitive certificate data OUT of Terraform state
- No automated secrets distribution needed between accounts
- Explicit, auditable security process
- Follows principle of least privilege
- Simplifies secret rotation workflow
- Each cluster maintains sovereignty over its own secrets

---

## Certificate Transfer Process

Detailed view of secure certificate transfer between Regional and Management operators.

```mermaid
graph LR
    subgraph Regional["Regional AWS Account<br/>(123456789012)"]
        TF["Terraform Apply<br/>maestro-infrastructure"]
        IoT["AWS IoT Core<br/>Create Certificate"]
        Out["Terraform Output<br/>maestro_agent_certificates<br/>(SENSITIVE)"]

        TF -->|Creates| IoT
        IoT -->|Certificate Data| Out
    end

    subgraph Extract["Regional Operator Actions"]
        Cmd1["terraform output -json<br/>maestro_agent_certificates"]
        JQ["jq '.&#91;&quot;management-01&quot;&#93;'<br/>> cert.json"]
        Encrypt["gpg --encrypt<br/>--recipient management-op<br/>cert.json"]

        Cmd1 --> JQ
        JQ --> Encrypt
    end

    subgraph Transfer["Secure Transfer"]
        Channel["Encrypted Channel<br/>───────────<br/>Options:<br/>• GPG-encrypted email<br/>• AWS Secrets Manager cross-account<br/>• HashiCorp Vault transit<br/>• Secure file share (Box, OneDrive)<br/>• Encrypted S3 bucket"]
    end

    subgraph Receive["Management Operator Actions"]
        Decrypt["gpg --decrypt<br/>cert.json.gpg<br/>> cert.json"]
        Verify["jq . cert.json<br/>(validate JSON)"]
        CLI["aws secretsmanager<br/>create-secret<br/>--secret-string file://cert.json"]
        Shred["shred -u cert.json<br/>(secure delete)"]

        Decrypt --> Verify
        Verify --> CLI
        CLI --> Shred
    end

    subgraph Management["Management AWS Account<br/>(987654321098)"]
        SM["AWS Secrets Manager<br/>management-01/maestro/<br/>agent-mqtt-cert"]
        TF2["Terraform Apply<br/>maestro-agent<br/>(references secret)"]

        SM --> TF2
    end

    Out --> Cmd1
    Encrypt --> Channel
    Channel --> Decrypt
    CLI --> SM

    style Out fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    style Channel fill:#ffe1e1,stroke:#cc0000,stroke-width:3px
    style SM fill:#d4edda,stroke:#28a745,stroke-width:2px
    style Encrypt fill:#ffcccc
    style Decrypt fill:#ccffcc
```

**Certificate Content:**
```json
{
  "certificateArn": "arn:aws:iot:us-east-1:123456789012:cert/abc...",
  "certificatePem": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
  "endpoint": "abc123.iot.us-east-1.amazonaws.com",
  "port": 8883,
  "consumerName": "management-01"
}
```

---

## Network Topology

Physical network layout showing VPC isolation and connectivity patterns.

```mermaid
graph TB
    subgraph Internet["Internet / AWS Global Services"]
        IoT_Global["AWS IoT Core<br/>Global Service<br/>Endpoint: *.iot.{region}.amazonaws.com:8883"]
    end

    subgraph Regional_Account["Regional AWS Account (123456789012)<br/>Region: us-east-1"]
        subgraph Regional_VPC["VPC: 10.0.0.0/16"]
            subgraph AZ1_R["Availability Zone 1"]
                Pub1_R["Public Subnet<br/>10.0.101.0/24<br/>NAT Gateway"]
                Priv1_R["Private Subnet<br/>10.0.1.0/24<br/>EKS Nodes"]
                DB1_R["RDS Subnet<br/>10.0.201.0/24"]
            end

            subgraph AZ2_R["Availability Zone 2"]
                Pub2_R["Public Subnet<br/>10.0.102.0/24<br/>NAT Gateway"]
                Priv2_R["Private Subnet<br/>10.0.2.0/24<br/>EKS Nodes"]
                DB2_R["RDS Subnet<br/>10.0.202.0/24"]
            end

            IGW_R["Internet Gateway"]
            ALB_R["Application Load Balancer<br/>(Optional - Admin Access)"]

            Priv1_R -->|Route 0.0.0.0/0| Pub1_R
            Priv2_R -->|Route 0.0.0.0/0| Pub2_R
            Pub1_R --> IGW_R
            Pub2_R --> IGW_R

            RDS_R["RDS PostgreSQL<br/>Multi-AZ<br/>Security Group:<br/>Port 5432 from EKS only"]

            DB1_R -.->|Primary| RDS_R
            DB2_R -.->|Standby| RDS_R

            Priv1_R -->|Private connection| RDS_R
            Priv2_R -->|Private connection| RDS_R
        end
    end

    subgraph Mgmt_Account["Management AWS Account (987654321098)<br/>Region: us-east-1"]
        subgraph Mgmt_VPC["VPC: 10.1.0.0/16"]
            subgraph AZ1_M["Availability Zone 1"]
                Pub1_M["Public Subnet<br/>10.1.101.0/24<br/>NAT Gateway"]
                Priv1_M["Private Subnet<br/>10.1.1.0/24<br/>EKS Nodes<br/>Maestro Agent"]
            end

            subgraph AZ2_M["Availability Zone 2"]
                Pub2_M["Public Subnet<br/>10.1.102.0/24<br/>NAT Gateway"]
                Priv2_M["Private Subnet<br/>10.1.2.0/24<br/>EKS Nodes"]
            end

            IGW_M["Internet Gateway"]

            Priv1_M -->|Route 0.0.0.0/0| Pub1_M
            Priv2_M -->|Route 0.0.0.0/0| Pub2_M
            Pub1_M --> IGW_M
            Pub2_M --> IGW_M
        end
    end

    IGW_R -->|HTTPS/TLS<br/>Port 8883| IoT_Global
    IGW_M -->|HTTPS/TLS<br/>Port 8883| IoT_Global

    NoPath["❌ NO DIRECT NETWORK PATH<br/>between Regional VPC and Management VPC"]

    Regional_VPC -.->|No peering<br/>No transit gateway<br/>No VPN| NoPath
    NoPath -.->|No peering<br/>No transit gateway<br/>No VPN| Mgmt_VPC

    style IoT_Global fill:#d4edda,stroke:#28a745,stroke-width:3px
    style RDS_R fill:#e8e8ff,stroke:#6666ff,stroke-width:2px
    style NoPath fill:#ffe1e1,stroke:#cc0000,stroke-width:3px
    style Priv1_R fill:#e1f5ff
    style Priv2_R fill:#e1f5ff
    style Priv1_M fill:#ffe1e1
    style Priv2_M fill:#ffe1e1
```

**Key Network Characteristics:**
- **Complete VPC Isolation**: No VPC peering, no Transit Gateway, no VPN between Regional and Management VPCs
- **Internet Gateway Only**: All clusters access IoT Core through NAT Gateway → Internet Gateway → AWS IoT endpoint
- **Private EKS Clusters**: Control planes have private endpoints only (no public access)
- **RDS Isolation**: Database accessible only from Regional EKS cluster security group
- **Multi-AZ Deployment**: High availability across multiple availability zones
- **Security**: All traffic encrypted in transit (TLS 1.2+)

---

## Related Documentation

- [Terraform Modules](../terraform/modules/) - Infrastructure as Code implementation
  - [maestro-infrastructure](../terraform/modules/maestro-infrastructure/) - Regional cluster resources
  - [maestro-agent](../terraform/modules/maestro-agent/) - Management cluster resources
