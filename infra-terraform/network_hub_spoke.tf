# =============================================================================
# Patron 6: Hub-and-Spoke con VPC Peering (gratis) en lugar de Transit Gateway.
#
#   VPC-HUB          10.0.0.0/16  Bastion (publica) + NLB de transito (privada)
#   VPC-SPOKE-APP    10.1.0.0/16  ECS Fargate, ALB interno, VPC Link, RDS
#   VPC-SPOKE-LEGACY 10.2.0.0/16  EC2 Lift-and-Shift (sin IGW: totalmente privada)
#
#   Peering:  HUB <-> APP   y   HUB <-> LEGACY.   NO existe peering APP <-> LEGACY.
#
# El peering NO es transitivo: un paquete 10.1.x -> 10.2.x no puede "atravesar" el Hub.
# Por eso el trafico App -> Legacy entra al Hub y lo reenvia un NLB interno del Hub
# (ver hub_transit.tf): el Hub es el unico punto de union entre spokes.
# =============================================================================

locals {
  hub_cidr    = "10.0.0.0/16"
  app_cidr    = "10.1.0.0/16"
  legacy_cidr = "10.2.0.0/16"

  hub_public_cidrs    = ["10.0.1.0/24"]
  hub_private_cidrs   = ["10.0.11.0/24", "10.0.12.0/24"]
  app_public_cidrs    = ["10.1.1.0/24", "10.1.2.0/24"]
  app_private_cidrs   = ["10.1.11.0/24", "10.1.12.0/24"]
  legacy_private_cidr = "10.2.1.0/24"
}

# ---------------------------------------------------------------- VPC-HUB ----
resource "aws_vpc" "hub" {
  cidr_block           = local.hub_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc-hub" }
}

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "${local.name}-igw-hub" }
}

resource "aws_subnet" "hub_public" {
  count                   = length(local.hub_public_cidrs)
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = local.hub_public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-hub-public-${count.index + 1}" }
}

resource "aws_subnet" "hub_private" {
  count             = length(local.hub_private_cidrs)
  vpc_id            = aws_vpc.hub.id
  cidr_block        = local.hub_private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name}-hub-transit-${count.index + 1}" }
}

# ---------------------------------------------------------- VPC-SPOKE-APP ----
resource "aws_vpc" "app" {
  cidr_block           = local.app_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc-spoke-app" }
}

# IGW solo para que Fargate descargue imagenes de ECR e invoque Lambda sin NAT Gateway
# (ahorro de creditos). Los Security Groups de las tareas no aceptan trafico de Internet.
resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = { Name = "${local.name}-igw-spoke-app" }
}

resource "aws_subnet" "app_public" {
  count             = length(local.app_public_cidrs)
  vpc_id            = aws_vpc.app.id
  cidr_block        = local.app_public_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name}-app-tasks-${count.index + 1}" }
}

resource "aws_subnet" "app_private" {
  count             = length(local.app_private_cidrs)
  vpc_id            = aws_vpc.app.id
  cidr_block        = local.app_private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name}-app-private-${count.index + 1}" }
}

# ------------------------------------------------------- VPC-SPOKE-LEGACY ----
resource "aws_vpc" "legacy" {
  cidr_block           = local.legacy_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc-spoke-legacy" }
}

resource "aws_subnet" "legacy_private" {
  vpc_id            = aws_vpc.legacy.id
  cidr_block        = local.legacy_private_cidr
  availability_zone = local.azs[0]
  tags              = { Name = "${local.name}-legacy-private" }
}

# ------------------------------------------------------------ VPC Peering ----
resource "aws_vpc_peering_connection" "hub_app" {
  vpc_id      = aws_vpc.hub.id
  peer_vpc_id = aws_vpc.app.id
  auto_accept = true
  tags        = { Name = "${local.name}-peering-hub-app" }
}

resource "aws_vpc_peering_connection" "hub_legacy" {
  vpc_id      = aws_vpc.hub.id
  peer_vpc_id = aws_vpc.legacy.id
  auto_accept = true
  tags        = { Name = "${local.name}-peering-hub-legacy" }
}

# ----------------------------------------------------------- Route tables ----
# HUB publica: Internet + ambos spokes
resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }
  route {
    cidr_block                = local.app_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_app.id
  }
  route {
    cidr_block                = local.legacy_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_legacy.id
  }
  tags = { Name = "${local.name}-rt-hub-public" }
}

# HUB privada (transito): solo ambos spokes
resource "aws_route_table" "hub_private" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block                = local.app_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_app.id
  }
  route {
    cidr_block                = local.legacy_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_legacy.id
  }
  tags = { Name = "${local.name}-rt-hub-transit" }
}

# SPOKE-APP subred de tareas: Internet (ECR/Lambda) + Hub. Sin ruta a 10.2.0.0/16.
resource "aws_route_table" "app_public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
  route {
    cidr_block                = local.hub_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_app.id
  }
  tags = { Name = "${local.name}-rt-app-tasks" }
}

# SPOKE-APP privada (ALB, VPC Link, RDS): solo Hub
resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block                = local.hub_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_app.id
  }
  tags = { Name = "${local.name}-rt-app-private" }
}

# SPOKE-LEGACY: solo Hub. Sin Internet, sin ruta a 10.1.0.0/16.
resource "aws_route_table" "legacy_private" {
  vpc_id = aws_vpc.legacy.id

  route {
    cidr_block                = local.hub_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_legacy.id
  }
  tags = { Name = "${local.name}-rt-legacy-private" }
}

resource "aws_route_table_association" "hub_public" {
  count          = length(aws_subnet.hub_public)
  subnet_id      = aws_subnet.hub_public[count.index].id
  route_table_id = aws_route_table.hub_public.id
}

resource "aws_route_table_association" "hub_private" {
  count          = length(aws_subnet.hub_private)
  subnet_id      = aws_subnet.hub_private[count.index].id
  route_table_id = aws_route_table.hub_private.id
}

resource "aws_route_table_association" "app_public" {
  count          = length(aws_subnet.app_public)
  subnet_id      = aws_subnet.app_public[count.index].id
  route_table_id = aws_route_table.app_public.id
}

resource "aws_route_table_association" "app_private" {
  count          = length(aws_subnet.app_private)
  subnet_id      = aws_subnet.app_private[count.index].id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "legacy_private" {
  subnet_id      = aws_subnet.legacy_private.id
  route_table_id = aws_route_table.legacy_private.id
}
