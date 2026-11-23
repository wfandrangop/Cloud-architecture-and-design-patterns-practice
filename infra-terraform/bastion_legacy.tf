# =============================================================================
# Patron 8: Bastion Host  +  Patron 7: Lift-and-Shift (EC2 legacy)
# =============================================================================

# ------------------------------------------------------------ Bastion SG ----
resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion-sg"
  description = "SSH solo desde la IP del administrador"
  vpc_id      = aws_vpc.hub.id

  ingress {
    description = "SSH desde mi IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-bastion-sg" }
}

# Unica maquina con IP publica y puerto 22 abierto
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.hub_public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = var.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y mariadb105 nmap-ncat
    echo "MiniStore Bastion - VPC-Hub" > /etc/motd
  EOF

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${local.name}-bastion" }
}

# ------------------------------------------------------------- Legacy SG ----
resource "aws_security_group" "legacy" {
  name        = "${local.name}-legacy-sg"
  description = "Inventario heredado: solo accesible desde el Hub"
  vpc_id      = aws_vpc.legacy.id

  ingress {
    description = "SSH solo desde la subred del Bastion (VPC-Hub)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.hub_public_cidrs
  }

  ingress {
    description = "Ping desde el Bastion (demo de aislamiento)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = local.hub_public_cidrs
  }

  ingress {
    description = "API de inventario desde el NLB de transito (y admin desde el Bastion)"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = concat(local.hub_private_cidrs, local.hub_public_cidrs)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.hub_cidr]
  }

  tags = { Name = "${local.name}-legacy-sg" }
}

# --------------------------------------------- EC2 Lift-and-Shift (Rehost) ----
# El codigo on-premise (legacy-onpremise-app/) se copia TAL CUAL: mismo script, misma
# unidad systemd, misma IP (10.2.1.10). No hay refactor, solo cambia donde corre.
resource "aws_instance" "legacy" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.legacy_private.id
  private_ip             = var.legacy_private_ip
  vpc_security_group_ids = [aws_security_group.legacy.id]
  key_name               = var.key_name
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name

  user_data = templatefile("${path.module}/templates/legacy-userdata.sh.tftpl", {
    app_code     = file("${path.module}/../legacy-onpremise-app/inventory_server.py")
    service_unit = file("${path.module}/../legacy-onpremise-app/ministore-inventory.service")
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${local.name}-legacy-inventory" }
}
