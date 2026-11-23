# MiniStore Express: patrones de arquitectura cloud en AWS

Portal de **órdenes de compra** de un e-commerce que depende de un sistema de inventario heredado (*legacy*). El sistema heredado se migra a AWS con **Lift-and-Shift**, y el nuevo núcleo de órdenes, hecho en **Spring Boot 4**, lo protege con **Circuit Breaker, Retry y Timeout**. Así una caída o lentitud del inventario nunca hace perder una venta. Toda la infraestructura se crea con **Terraform** sobre AWS Academy Learner Lab.

| Capa | Tecnología |
| --- | --- |
| Frontend | React 19 + Vite 8, servido por Nginx (reverse proxy) |
| Backend | Java 21, Spring Boot 4.2, Resilience4j 2.4, AWS SDK v2 |
| Legacy | Python 3 (solo librería estándar) + systemd |
| Serverless | AWS Lambda (Python 3.13) |
| Infraestructura | Terraform (AWS provider 6.x): VPC Peering, EC2, ECR, ECS Fargate, ALB, NLB, API Gateway, RDS MySQL 8.4 |

## Arquitectura

```text
 Navegador ──► Tarea Fargate "frontend" (Nginx :80, IP pública)
                 │  location /api/  ->  proxy_pass  (Reverse Proxy)
                 ▼
          Amazon API Gateway (HTTP API, throttling 20 rps / burst 40)
                 │  VPC Link
═════════════════│═══════════════════════════════════════════════════════════════
 VPC-SPOKE-APP 10.1.0.0/16                                                          
                 ▼                                                                   
          ALB interno :80 ──► ECS Fargate order-service  x2 (Java, :8080)
                                 │ JDBC          │ Invoke (Event)      │ HTTP + CB/Retry/Timeout 2s
                                 ▼               ▼                     │
                             RDS MySQL      Lambda receipt-processor   │
═════════════════════════════════════════════════ peering HUB<->APP ═══│═════════════
 VPC-HUB 10.0.0.0/16                                                   ▼
   Bastion (subred pública, SSH solo desde tu IP)        NLB interno de tránsito :8081
═════════════════════════════════════════════════ peering HUB<->LEGACY ═│════════════
 VPC-SPOKE-LEGACY 10.2.0.0/16  (sin Internet Gateway)                   ▼
                                           EC2 legacy 10.2.1.10:8081 (Lift-and-Shift)
```

**No existe peering entre APP y LEGACY.** Los *spokes* solo se comunican a través del Hub.

## Los 8 patrones en el código

| # | Patrón | Dónde está |
| --- | --- | --- |
| 1 | **Circuit Breaker** | `backend-java/.../inventory/ResilientInventoryService.java` + `application.yml`: ventana de 4 llamadas, mínimo 3, ≥ 50 % de fallos → **OPEN** durante 15 s, luego HALF_OPEN. Fallback: la orden se guarda como `PENDING_VALIDATION`. |
| 2 | **Retry** | Mismo servicio: 3 intentos con 500 ms de espera ante timeout, error de red o 5xx. |
| 3 | **Timeout** | `TimeLimiter` de 2 s por intento (cancela el hilo virtual). El *read-timeout* del socket es de 3 s y solo actúa como red de seguridad. |
| 4 | **Serverless y contenedores** | `infra-terraform/ecs_ecr.tf` (ECR + Fargate para Java y para React/Nginx), `lambda-receipt/handler.py` y `ReceiptNotifier.java` (invocación asíncrona). |
| 5 | **API Gateway, Load Balancer y Reverse Proxy** | `frontend-react/nginx/default.conf.template` (Nginx → API GW), `infra-terraform/apigateway.tf` (HTTP API + throttling + VPC Link), ALB interno en `ecs_ecr.tf` que reparte entre 2 tareas. |
| 6 | **Hub-and-Spoke** | `infra-terraform/network_hub_spoke.tf` (3 VPCs, 2 peerings, tablas de rutas) y `hub_transit.tf` (NLB de tránsito en el Hub). |
| 7 | **Lift-and-Shift** | `legacy-onpremise-app/`: el **mismo** script y la misma unidad systemd que corren on-premise se copian sin cambios a la EC2, con la misma IP (`bastion_legacy.tf` + `templates/legacy-userdata.sh.tftpl`). |
| 8 | **Bastion Host** | `bastion_legacy.tf`: única EC2 con IP pública. Es el único origen SSH permitido hacia el legado y el único túnel posible hacia RDS. |

### Cadena de resiliencia

```text
CircuitBreaker   (externo)  OPEN => fallback inmediato (~0 ms), no toca la red
  └─ Retry                  3 intentos, 500 ms entre intentos
       └─ TimeLimiter       2 s por intento
            └─ GET http://<nlb-hub>:8081/inventory/{id}
```

Se usa el estilo **funcional** de Resilience4j para garantizar ese orden. Con anotaciones, el orden por defecto es `Retry(CircuitBreaker(...))`. Los umbrales están en `application.yml` y los carga el starter `resilience4j-spring-boot4`.

Estados de una orden: `CONFIRMED` (hay stock), `OUT_OF_STOCK` (el legado respondió sin stock) y `PENDING_VALIDATION` (fallback, con `fallbackReason` = `CIRCUIT_OPEN` | `TIMEOUT` | `LEGACY_ERROR`).

### API del backend

| Método | Ruta | Descripción |
| --- | --- | --- |
| GET | `/api/products` | Catálogo de 4 productos (desde RDS) |
| POST | `/api/orders` | `{ "productId": 1, "quantity": 2, "customerEmail": "user@uce.edu.ec" }` |
| GET | `/api/orders` | Últimas 20 órdenes |
| GET | `/api/orders/health-circuit` | Estado del Circuit Breaker de la tarea que responde |

Cada respuesta incluye `servedBy`, el hostname de la tarea Fargate, como evidencia del balanceo del ALB. También incluye `inventoryAttempts` e `inventoryLatencyMs` como evidencia de Retry y Timeout.

## Decisiones de diseño (y por qué difieren del boceto inicial)

1. **El peering no es transitivo.** Con peerings HUB↔APP y HUB↔LEGACY, Java (10.1.x) **no puede** llegar a 10.2.1.10 aunque haya rutas. Por eso Java llama a un **NLB interno del Hub**, y ese NLB reenvía al legado. Así el Hub es, de verdad, el punto de tránsito entre spokes. `preserve_client_ip = false` es obligatorio para que el legado responda por el Hub.
2. **Sin NAT Gateway.** Un NAT en el Hub **no sirve** a los spokes, porque el peering no permite usar el NAT o el IGW de la VPC vecina. Para ahorrar créditos, las tareas Fargate van en subredes con IGW e IP pública, que solo usan para salir hacia ECR y Lambda. Sus Security Groups solo aceptan tráfico del ALB. El legado no tiene ninguna salida a Internet y no la necesita, porque solo usa python3, que ya viene en Amazon Linux 2023. En producción se usarían subredes privadas con VPC Endpoints o NAT.
3. **El ALB y el VPC Link están en VPC-Spoke-App**, junto a sus tareas, porque es la configuración que ECS y API Gateway soportan sin trucos.
4. **Cada tarea Fargate tiene su propio Circuit Breaker.** El ALB reparte las órdenes entre las 2 tareas, así que para abrir ambos circuitos hacen falta unas 3 órdenes fallidas por tarea. Por eso el botón de la demo envía **6 órdenes**. El panel de React muestra un badge por tarea.
5. **RDS MySQL 8.4**, porque 8.0 ya está en soporte extendido, que se cobra aparte.
6. **IAM del Learner Lab:** no se crea ningún rol. Se usan `LabRole` y `LabInstanceProfile` mediante bloques `data`.
7. **Health check y Circuit Breaker separados:** el health indicator del circuito está desactivado. Así un circuito OPEN no hace que el ALB saque las tareas de servicio.

## Estructura

```text
├── backend-java/            Spring Boot 4 + Resilience4j + Dockerfile (tests incluidos)
├── frontend-react/          React + Vite, nginx/default.conf.template, Dockerfile
├── legacy-onpremise-app/    inventory_server.py + ministore-inventory.service (systemd)
├── lambda-receipt/          handler.py (receipt-processor)
├── infra-terraform/
│   ├── main.tf              provider, LabRole / LabInstanceProfile, AMI
│   ├── variables.tf / outputs.tf / terraform.tfvars.example
│   ├── network_hub_spoke.tf 3 VPCs, subredes, peering, route tables
│   ├── hub_transit.tf       NLB de tránsito Hub -> Legacy
│   ├── bastion_legacy.tf    Bastion + EC2 Lift-and-Shift
│   ├── ecs_ecr.tf           ECR, cluster, ALB, task definitions, servicios
│   ├── database_lambda.tf   RDS MySQL + Lambda
│   ├── apigateway.tf        HTTP API, VPC Link, throttling, access logs
│   └── templates/legacy-userdata.sh.tftpl
├── scripts/                 deploy.sh, frontend-url.sh, destroy.sh
└── docker-compose.yml       todo el sistema en local
```

## Ejecución local

```bash
# Opción A: todo con Docker  ->  http://localhost:3000
docker compose up --build

# Opción B: sin Docker
python legacy-onpremise-app/inventory_server.py                          # :8081
cd backend-java && SPRING_PROFILES_ACTIVE=local ./mvnw spring-boot:run     # :8080 (H2 en memoria)
cd frontend-react && npm install && npm run dev                          # :5173 (Vite hace de proxy de /api)

# Simular fallas del legado
curl -X POST "http://localhost:8081/admin/simulate?mode=slow"   # o down / normal
```

Tests: `cd backend-java && ./mvnw test`. Prueban que el modo lento produce 3 intentos cortados por timeout y que el modo caído abre el circuito, tras lo cual la siguiente orden responde en menos de 20 ms sin tocar el legado.

## Despliegue en AWS Academy

1. Inicia el Learner Lab. En **AWS Details**, copia las credenciales a `~/.aws/credentials` y descarga `labsuser.pem`.
2. Configura las variables:
   ```bash
   cp infra-terraform/terraform.tfvars.example infra-terraform/terraform.tfvars
   curl -s https://checkip.amazonaws.com     # pon esa IP con /32 en my_ip_cidr
   ```
3. Con Docker Desktop encendido, desde **Git Bash**:
   ```bash
   ./scripts/deploy.sh
   ```
   El script crea ECR, construye y sube las 2 imágenes, aplica el resto de Terraform (RDS tarda entre 5 y 10 min), redespliega ECS e imprime la URL del portal.
4. Al terminar: `./scripts/destroy.sh`.

> La IP pública del frontend cambia si la tarea se reinicia. Para obtenerla de nuevo, ejecuta `./scripts/frontend-url.sh`.

**Si `docker push` falla con `failed commit on ref ... timeout awaiting response headers`:** es un corte de red al subir capas grandes a ECR, no un error de Terraform. `deploy.sh` reintenta hasta 5 veces, y ECR conserva las capas ya subidas. Si sigue fallando, limita las subidas en paralelo: en Docker Desktop, abre **Settings → Docker Engine**, añade `"max-concurrent-uploads": 1` al JSON y pulsa **Apply & restart**. Luego vuelve a ejecutar `./scripts/deploy.sh`. Se puede repetir sin problema, porque Terraform no recrea lo que ya existe.

## Guion de demostración

Configura SSH una vez (`~/.ssh/config`) con los valores de `terraform output`:

```text
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

**1. Flujo normal (contenedores + serverless + proxy + LB).** En el portal crea una orden: aparece `CONFIRMED`, con 1 intento y el nombre de la tarea (`ip-10-1-…`). Si creas varias, verás alternar las 2 tareas. El recibo se ve en CloudWatch Logs:
```bash
aws logs tail /aws/lambda/ministore-receipt-processor --follow
```

**2. Timeout + Retry.**
```bash
ssh ministore-bastion 'curl -s -X POST "http://10.2.1.10:8081/admin/simulate?mode=slow"'
aws logs tail /ecs/ministore-order-service --follow     # en otra terminal
```
Crea una orden. El log muestra `[TIMEOUT]` a los 2,0 s y luego `[RETRY] intento 1…2`. Tras 3 intentos (unos 7 s en total) la orden queda `PENDING_VALIDATION / TIMEOUT`.

**3. Circuit Breaker.**
```bash
ssh ministore-bastion 'curl -s -X POST "http://10.2.1.10:8081/admin/simulate?mode=down"'
```
Pulsa **Ráfaga x6**. Los badges pasan de `CLOSED` a `OPEN` y las últimas órdenes responden en pocos ms con 0 intentos y `fallbackReason = CIRCUIT_OPEN`. A los 15 s el circuito pasa a `HALF_OPEN`. Vuelve a `mode=normal` y, con 2 órdenes correctas, el circuito regresa a `CLOSED`.

**4. Bastion y aislamiento Hub-and-Spoke.**
```bash
ping 10.2.1.10                       # desde tu PC: sin respuesta (IP privada, sin ruta)
ssh ministore-legacy                 # funciona SOLO saltando por el Bastion
  systemctl status ministore-inventory   # mismo servicio que on-premise (Lift-and-Shift)
  curl -m 3 http://<rds_endpoint>:3306   # falla: Legacy no puede ver el spoke App
exit
ssh ministore-bastion
  ping -c 2 10.2.1.10                                 # el Hub sí llega a Legacy
  mysql -h <rds_endpoint> -u admin -p ministore -e "select id,status,fallback_reason from purchase_orders;"
```
Túnel a RDS desde tu PC (DBeaver o Workbench en `localhost:3307`):
```bash
ssh -i labsuser.pem -N -L 3307:<rds_endpoint>:3306 ec2-user@<bastion_public_ip>
```
