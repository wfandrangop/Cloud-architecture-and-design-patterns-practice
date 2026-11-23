# =============================================================================
# RDS MySQL (VPC-Spoke-App, privada)  +  Patron 4 (Serverless): AWS Lambda
# =============================================================================

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "MySQL: order-service y tunel SSH desde el Bastion"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "MySQL desde las tareas Java"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.java_tasks.id]
  }

  ingress {
    description = "MySQL desde el Bastion (VPC-Hub, via peering)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = local.hub_public_cidrs
  }

  tags = { Name = "${local.name}-rds-sg" }
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.app_private[*].id
}

resource "aws_db_instance" "main" {
  identifier              = "${local.name}-mysql"
  engine                  = "mysql"
  engine_version          = "8.4" # 8.0 ya esta en soporte extendido (cobro extra)
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = "ministore"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  apply_immediately       = true
}

# ---------------------------------------------------------------- Lambda ----
data "archive_file" "receipt" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-receipt"
  output_path = "${path.module}/build/receipt-processor.zip"
}

resource "aws_cloudwatch_log_group" "receipt" {
  name              = "/aws/lambda/${local.name}-receipt-processor"
  retention_in_days = 3
}

resource "aws_lambda_function" "receipt" {
  function_name    = "${local.name}-receipt-processor"
  role             = data.aws_iam_role.lab_role.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.receipt.output_path
  source_code_hash = data.archive_file.receipt.output_base64sha256
  timeout          = 10
  memory_size      = 128

  depends_on = [aws_cloudwatch_log_group.receipt]
}
