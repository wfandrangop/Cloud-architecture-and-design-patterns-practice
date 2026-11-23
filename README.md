# MiniStore Express — Cloud Architecture Patterns on AWS

![AWS](https://img.shields.io/badge/AWS-Academy%20Learner%20Lab-232F3E?style=flat-square&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-AWS%20Provider%206.x-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![Java](https://img.shields.io/badge/Java-21%20%7C%20Spring%20Boot%204.2-6DB33F?style=flat-square&logo=springboot&logoColor=white)
![React](https://img.shields.io/badge/React-19%20%7C%20Vite%208-61DAFB?style=flat-square&logo=react&logoColor=black)
![Docker](https://img.shields.io/badge/Docker-ECS%20Fargate%20%26%20ECR-2496ED?style=flat-square&logo=docker&logoColor=white)

An e-commerce **purchase-order portal** integrated with a legacy on-premises inventory system. The legacy service is migrated to AWS via a **Lift-and-Shift** strategy, while the new order-processing core—built with **Spring Boot 4**—protects it using **Circuit Breaker, Retry, and Timeout** patterns so inventory slowdowns or outages never result in lost sales. The entire infrastructure is provisioned with **Terraform** on AWS Academy Learner Lab.

## 📑 Table of Contents

- [Tech Stack](#-tech-stack)
- [System Architecture](#-system-architecture)
- [Implemented Cloud Patterns (8)](#-implemented-cloud-patterns-8)
- [Resilience Pipeline & Backend API](#-resilience-pipeline--backend-api)
- [Key Architectural Decisions](#-key-architectural-decisions)
- [Project Structure](#-project-structure)
- [Local Development](#-local-development)
- [Deployment on AWS Academy](#-deployment-on-aws-academy)
- [Live Demo Playbook](#-live-demo-playbook)

---

## 🛠 Tech Stack

| Layer | Technologies |
| :--- | :--- |
| **Frontend** | React 19 + Vite 8, served via Nginx (Reverse Proxy) |
| **Backend** | Java 21, Spring Boot 4.2, Resilience4j 2.4, AWS SDK v2 |
| **Legacy System** | Python 3 (standard library only) + `systemd` |
| **Serverless** | AWS Lambda (Python 3.13) |
| **Infrastructure** | Terraform (AWS Provider 6.x): VPC Peering, EC2, ECR, ECS Fargate, ALB, NLB, API Gateway, RDS MySQL 8.4 |

---

## 🏗 System Architecture

```text
 Browser ──► Fargate Task "frontend" (Nginx :80, Public IP)
               │  location /api/  ──►  proxy_pass (Reverse Proxy)
               ▼
        Amazon API Gateway (HTTP API, throttling: 20 rps / burst 40)
               │  VPC Link
═══════════════│══════════════════════════════════════════════════════════════════
 VPC-SPOKE-APP (10.1.0.0/16)
               ▼
        Internal ALB :80 ──► ECS Fargate order-service x2 (Java :8080)
                               │ JDBC          │ Invoke (Event)      │ HTTP + CB/Retry/Timeout (2s)
                               ▼               ▼                     │
                           RDS MySQL      Lambda receipt-processor   │
═══════════════════════════════════════════════ Peering HUB <-> APP ═│════════════
 VPC-HUB (10.0.0.0/16)                                               ▼
   Bastion Host (Public Subnet, SSH from your IP only)    Internal Transit NLB :8081
═══════════════════════════════════════════════ Peering HUB <-> LEGACY ═══════════
 VPC-SPOKE-LEGACY (10.2.0.0/16 — No Internet Gateway)                ▼
                                         Legacy EC2 10.2.1.10:8081 (Lift-and-Shift)
```

> [!IMPORTANT]
> **Strict Spoke Isolation:** There is **no direct VPC peering** between `VPC-SPOKE-APP` and `VPC-SPOKE-LEGACY`. All inter-spoke communication is routed strictly through `VPC-HUB`.

---

## 🧩 Implemented Cloud Patterns (8)

| # | Pattern | Implementation Details |
| :-: | :--- | :--- |
| **1** | **Circuit Breaker** | `backend-java/.../inventory/ResilientInventoryService.java` + `application.yml`: Sliding window of 4 calls, minimum 3 calls, $\ge 50\%$ failure threshold $\rightarrow$ transitions to **OPEN** for 15s, then `HALF_OPEN`. Fallback saves orders as `PENDING_VALIDATION`. |
| **2** | **Retry** | Same service: Up to **3 attempts** with a **500ms** backoff on timeouts, network errors, or HTTP 5xx responses. |
| **3** | **Timeout** | `TimeLimiter` set to **2s** per attempt (cancels the virtual thread). The underlying socket read-timeout is **3s** as a secondary safety net. |
| **4** | **Serverless & Containers** | `infra-terraform/ecs_ecr.tf` (ECR + ECS Fargate for Java and React/Nginx), `lambda-receipt/handler.py`, and `ReceiptNotifier.java` (asynchronous event invocation). |
| **5** | **API Gateway, LB & Reverse Proxy** | `frontend-react/nginx/default.conf.template` (Nginx $\rightarrow$ API Gateway), `infra-terraform/apigateway.tf` (HTTP API + throttling + VPC Link), and an internal ALB in `ecs_ecr.tf` balancing traffic across 2 tasks. |
| **6** | **Hub-and-Spoke** | `infra-terraform/network_hub_spoke.tf` (3 isolated VPCs, 2 peering connections, custom route tables) and `hub_transit.tf` (transit NLB inside the Hub). |
| **7** | **Lift-and-Shift** | `legacy-onpremise-app/`: The **exact same** Python script and `systemd` unit running on-premises are rehosted unchanged onto EC2 with the same private IP (`bastion_legacy.tf` + `templates/legacy-userdata.sh.tftpl`). |
| **8** | **Bastion Host** | `bastion_legacy.tf`: The sole EC2 instance with a public IP. Serves as the only authorized SSH jump host into the legacy network and the only port-forwarding tunnel to RDS. |

---

## ⚡ Resilience Pipeline & Backend API

### Resilience Execution Chain

```text
CircuitBreaker (outer) ──► When OPEN: immediate fallback (~0ms), zero network calls
  └─ Retry             ──► Up to 3 attempts, 500ms interval between retries
       └─ TimeLimiter  ──► 2s hard limit per attempt
            └─ GET http://<nlb-hub>:8081/inventory/{id}
```

Resilience4j's **functional composition** style is used to enforce this exact decorator order (annotation-based defaults wrap as `Retry(CircuitBreaker(...))`). Thresholds are externalized in `application.yml` and auto-configured via `resilience4j-spring-boot4`.

**Order Lifecycle States:**
* `CONFIRMED` — Stock verified and reserved.
* `OUT_OF_STOCK` — Legacy system responded normally with insufficient inventory.
* `PENDING_VALIDATION` — Fallback triggered (`fallbackReason`: `CIRCUIT_OPEN` | `TIMEOUT` | `LEGACY_ERROR`).

### REST API Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/products` | Retrieves the 4-product catalog from RDS |
| `POST` | `/api/orders` | Creates an order: `{ "productId": 1, "quantity": 2, "customerEmail": "user@uce.edu.ec" }` |
| `GET` | `/api/orders` | Lists the 20 most recent orders |
| `GET` | `/api/orders/health-circuit` | Reports the Circuit Breaker state of the responding Fargate task |

> [!NOTE]
> Every API response includes `servedBy` (the Fargate task hostname) to prove ALB round-robin distribution, along with `inventoryAttempts` and `inventoryLatencyMs` to verify Retry and Timeout behavior in real time.

---

## 🧠 Key Architectural Decisions

1. **Non-Transitive VPC Peering:** With `HUB <-> APP` and `HUB <-> LEGACY` peerings, Java tasks (`10.1.x.x`) cannot route directly to `10.2.1.10` even with route table entries. Java calls an **internal NLB in `VPC-HUB`**, which forwards traffic to the legacy EC2 instance, making the Hub a true transit layer. Setting `preserve_client_ip = false` on the NLB target group is mandatory so return traffic routes back through the Hub.
2. **Zero NAT Gateways (Credit Optimization):** A NAT Gateway in the Hub cannot be shared with spoke VPCs over peering. To conserve AWS Academy lab credits, Fargate tasks run in subnets with an IGW and ephemeral public IPs strictly for outbound pulls from ECR and Lambda invocations, while Security Groups restrict inbound traffic exclusively to the ALB. The legacy EC2 has zero internet access (relying on pre-installed Python 3 in Amazon Linux 2023). *In a production environment, private subnets with VPC Interface Endpoints or NAT Gateways would be used.*
3. **Colocated ALB & VPC Link:** Both the internal ALB and API Gateway VPC Link reside in `VPC-SPOKE-APP` alongside the Fargate tasks, matching native AWS ECS/API Gateway integration constraints.
4. **Per-Task Circuit Breaker State:** Because the ALB balances requests across 2 Fargate tasks, roughly 3 failed requests *per task* are required to trip both circuits. The frontend includes a **Burst x6** button and displays independent status badges per task.
5. **RDS MySQL 8.4:** Selected over MySQL 8.0 to avoid AWS Extended Support surcharges.
6. **AWS Academy IAM Constraints:** Custom IAM role creation is blocked in Learner Labs; Terraform references pre-existing `LabRole` and `LabInstanceProfile` via `data` blocks.
7. **Decoupled Health Checks & Circuit Breaker:** Spring Boot's Circuit Breaker health indicator is disabled so an `OPEN` circuit does not cause the ALB to mark healthy Fargate containers as unhealthy.

---

## 📂 Project Structure

```text
├── backend-java/            # Spring Boot 4 + Resilience4j + Dockerfile + unit/integration tests
├── frontend-react/          # React 19 + Vite 8, nginx/default.conf.template, Dockerfile
├── legacy-onpremise-app/    # inventory_server.py + ministore-inventory.service (systemd)
├── lambda-receipt/          # handler.py (receipt-processor AWS Lambda)
├── infra-terraform/
│   ├── main.tf              # AWS provider, LabRole / LabInstanceProfile data sources, AMI lookup
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Bastion IP, RDS endpoint, API Gateway URL
│   ├── terraform.tfvars.example
│   ├── network_hub_spoke.tf # 3 VPCs, subnets, VPC peerings, route tables
│   ├── hub_transit.tf       # Internal transit NLB (Hub -> Legacy)
│   ├── bastion_legacy.tf    # Bastion Host + Lift-and-Shift EC2 instance
│   ├── ecs_ecr.tf           # ECR repos, ECS cluster, ALB, task definitions, Fargate services
│   ├── database_lambda.tf   # RDS MySQL 8.4 + Lambda function
│   ├── apigateway.tf        # HTTP API Gateway, VPC Link, throttling, CloudWatch access logs
│   └── templates/
│       └── legacy-userdata.sh.tftpl
├── scripts/
│   ├── deploy.sh            # End-to-end build, ECR push, and Terraform apply script
│   ├── frontend-url.sh      # Fetches the current public IP of the frontend Fargate task
│   └── destroy.sh           # Tears down all AWS resources cleanly
└── docker-compose.yml       # Full-stack local execution environment
```

---

## 💻 Local Development

### Option A: Run Entire Stack with Docker Compose
```bash
docker compose up --build
# Portal available at http://localhost:3000
```

### Option B: Run Services Individually (Without Docker)
```bash
# 1. Start legacy inventory server (:8081)
python legacy-onpremise-app/inventory_server.py

# 2. Start Spring Boot backend with in-memory H2 (:8080)
cd backend-java && SPRING_PROFILES_ACTIVE=local ./mvnw spring-boot:run

# 3. Start React dev server with Vite /api proxy (:5173)
cd frontend-react && npm install && npm run dev
```

### Simulate Legacy Faults & Run Tests
```bash
# Toggle legacy simulation modes: normal | slow | down
curl -X POST "http://localhost:8081/admin/simulate?mode=slow"

# Run Resilience4j verification tests (verifies 3 timeout retries & <20ms open-circuit fallback)
cd backend-java && ./mvnw test
```

---

## 🚀 Deployment on AWS Academy

1. Start your **AWS Academy Learner Lab**. Open **AWS Details**, copy your temporary credentials into `~/.aws/credentials`, and download `labsuser.pem`.
2. Configure your Terraform variables:
   ```bash
   cp infra-terraform/terraform.tfvars.example infra-terraform/terraform.tfvars
   curl -s https://checkip.amazonaws.com   # Add this IP with /32 to my_ip_cidr in terraform.tfvars
   ```
3. Ensure Docker Desktop is running, then run the deployment script from **Git Bash**:
   ```bash
   ./scripts/deploy.sh
   ```
   *This script provisions ECR repositories, builds and pushes both Docker images, applies the remaining Terraform stack (RDS takes ~5–10 minutes), forces a new ECS deployment, and prints the live frontend URL.*
4. Tear down all infrastructure when finished:
   ```bash
   ./scripts/destroy.sh
   ```

> [!TIP]
> **Dynamic Frontend IP:** Because the frontend Fargate task uses an ephemeral public IP, its address changes if the task restarts. Run `./scripts/frontend-url.sh` anytime to retrieve the updated URL.

> [!WARNING]
> **Docker Push Timeouts (`failed commit on ref ... timeout awaiting response headers`):** This is caused by transient network drops when uploading large image layers to ECR, not a Terraform bug. `deploy.sh` automatically retries up to 5 times while ECR preserves already-uploaded layers. If timeouts persist, open **Docker Desktop $\rightarrow$ Settings $\rightarrow$ Docker Engine**, add `"max-concurrent-uploads": 1` to the JSON config, click **Apply & restart**, and re-run `./scripts/deploy.sh`.

---

## 🎬 Live Demo Playbook

Configure your SSH client once (`~/.ssh/config`) using values from `terraform output`:

```sshconfig
Host ministore-bastion
  HostName <bastion_public_ip>
  User ec2-user
  IdentityFile ~/labsuser.pem

Host ministore-legacy
  HostName 10.2.1.10
  User ec2-user
  IdentityFile ~/labsuser.pem
  ProxyJump ministore-bastion
```

### 1. Nominal Flow (Containers + Serverless + Reverse Proxy + ALB)
Place an order from the web portal. It returns `CONFIRMED` in **1 attempt**, displaying the serving Fargate task hostname (`ip-10-1-...`). Submit multiple orders to watch the ALB alternate between both tasks. Verify asynchronous receipt generation in CloudWatch Logs:
```bash
aws logs tail /aws/lambda/ministore-receipt-processor --follow
```

### 2. Timeout + Retry Patterns
Switch the legacy server into high-latency mode (`5s` delay) and tail ECS logs:
```bash
ssh ministore-bastion 'curl -s -X POST "http://10.2.1.10:8081/admin/simulate?mode=slow"'
aws logs tail /ecs/ministore-order-service --follow
```
Create an order in the UI. Logs will show `[TIMEOUT]` firing at **2.0s**, followed by `[RETRY]` attempts 1 and 2. After 3 failed attempts (~7s total), the order gracefully degrades to `PENDING_VALIDATION` (`fallbackReason: TIMEOUT`).

### 3. Circuit Breaker Pattern
Simulate a total legacy outage (`HTTP 500`):
```bash
ssh ministore-bastion 'curl -s -X POST "http://10.2.1.10:8081/admin/simulate?mode=down"'
```
Click **Burst x6** in the UI. Both task badges transition from `CLOSED` to `OPEN`, and subsequent orders complete in **<20ms** with `0` inventory attempts (`fallbackReason: CIRCUIT_OPEN`). After **15 seconds**, the circuit enters `HALF_OPEN`. Restore `mode=normal` and submit 2 successful orders to return the circuit to `CLOSED`.

### 4. Bastion Host & Hub-and-Spoke Isolation
Verify zero-trust network segmentation and database tunneling:
```bash
# 1. Direct access from your local machine fails (private IP, no public route)
ping 10.2.1.10

# 2. SSH jump via Bastion succeeds
ssh ministore-legacy
  systemctl status ministore-inventory   # Rehosted on-premises service (Lift-and-Shift)
  curl -m 3 http://<rds_endpoint>:3306   # Fails: Legacy spoke cannot reach App spoke
exit

# 3. Verify Hub-to-Legacy connectivity and query RDS from Bastion
ssh ministore-bastion
  ping -c 2 10.2.1.10
  mysql -h <rds_endpoint> -u admin -p ministore -e "SELECT id, status, fallback_reason FROM purchase_orders;"
```
**Optional RDS Port Forwarding (for DBeaver / MySQL Workbench on `localhost:3307`):**
```bash
ssh -i ~/labsuser.pem -N -L 3307:<rds_endpoint>:3306 ec2-user@<bastion_public_ip>
```
