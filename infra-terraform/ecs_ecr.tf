# =============================================================================
# Patron 4 (Contenedores): ECR + ECS Fargate
# Patron 5 (Load Balancer): ALB interno que reparte entre 2 tareas Java
# =============================================================================

# ------------------------------------------------------------------- ECR ----
resource "aws_ecr_repository" "java" {
  name                 = "ministore-java"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "ministore-react-nginx"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ----------------------------------------------------------- ECS cluster ----
resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
}

resource "aws_cloudwatch_log_group" "java" {
  name              = "/ecs/${local.name}-order-service"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name}-frontend"
  retention_in_days = 3
}

# ------------------------------------------------------- Security groups ----
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB interno: solo recibe trafico del VPC Link de API Gateway"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "HTTP desde el VPC Link"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }

  egress {
    description = "Hacia las tareas Java"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.app_cidr]
  }

  tags = { Name = "${local.name}-alb-sg" }
}

resource "aws_security_group" "java_tasks" {
  name        = "${local.name}-java-tasks-sg"
  description = "order-service: solo acepta trafico del ALB"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "HTTP 8080 desde el ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "ECR, Lambda, RDS y NLB de transito"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-java-tasks-sg" }
}

resource "aws_security_group" "frontend_tasks" {
  name        = "${local.name}-frontend-sg"
  description = "Portal React/Nginx"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTP publico al portal"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.frontend_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-frontend-sg" }
}

# ------------------------------------------------------------ ALB interno ----
resource "aws_lb" "app" {
  name               = "${local.name}-app-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.app_private[*].id
  security_groups    = [aws_security_group.alb.id]
  idle_timeout       = 60
}

resource "aws_lb_target_group" "java" {
  name                 = "${local.name}-java-tg"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.app.id
  deregistration_delay = 15

  health_check {
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.java.arn
  }
}

# -------------------------------------------------- Task def: order-service ----
resource "aws_ecs_task_definition" "java" {
  family                   = "${local.name}-order-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "order-service"
    image        = "${aws_ecr_repository.java.repository_url}:${var.java_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "DB_URL", value = "jdbc:mysql://${aws_db_instance.main.address}:3306/ministore?createDatabaseIfNotExist=true&allowPublicKeyRetrieval=true&sslMode=PREFERRED" },
      { name = "DB_USERNAME", value = var.db_username },
      # Simplificacion del laboratorio: en produccion usar "secrets" con Secrets Manager/SSM
      { name = "DB_PASSWORD", value = var.db_password },
      { name = "LEGACY_INVENTORY_URL", value = "http://${aws_lb.legacy_transit.dns_name}:8081" },
      { name = "RECEIPT_LAMBDA_NAME", value = aws_lambda_function.receipt.function_name },
      { name = "AWS_REGION", value = var.aws_region },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.java.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "java"
      }
    }
  }])
}

resource "aws_ecs_service" "java" {
  name                              = "${local.name}-order-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.java.arn
  desired_count                     = var.java_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.app_public[*].id
    security_groups  = [aws_security_group.java_tasks.id]
    assign_public_ip = true # sin NAT Gateway: la IP publica solo se usa para salir (ECR/Lambda)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.java.arn
    container_name   = "order-service"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.app]
}

# --------------------------------------------------- Task def: frontend ----
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "frontend"
    image        = "${aws_ecr_repository.frontend.repository_url}:${var.frontend_image_tag}"
    essential    = true
    portMappings = [{ containerPort = 80, protocol = "tcp" }]
    environment = [
      # Nginx reenvia /api/* aqui (reverse proxy -> API Gateway)
      { name = "API_UPSTREAM", value = aws_apigatewayv2_api.main.api_endpoint },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.frontend.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "nginx"
      }
    }
  }])
}

resource "aws_ecs_service" "frontend" {
  name            = "${local.name}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.app_public[0].id]
    security_groups  = [aws_security_group.frontend_tasks.id]
    assign_public_ip = true # el portal se abre en http://<IP publica de la tarea>
  }
}
