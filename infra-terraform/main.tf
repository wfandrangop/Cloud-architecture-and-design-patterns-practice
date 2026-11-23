terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ministore-express"
      ManagedBy = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# AWS Academy Learner Lab: no se permite crear roles IAM (aws_iam_role -> AccessDenied).
# Se reutilizan el rol y el instance profile que ya existen en la cuenta del laboratorio.
# -----------------------------------------------------------------------------
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# Amazon Linux 2023 (trae python3 de serie: el legado no necesita Internet para instalarse)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  name = var.project_name
  azs  = var.availability_zones

  # Acepta "157.100.87.2" o "157.100.87.2/32"
  admin_cidr = strcontains(var.my_ip_cidr, "/") ? var.my_ip_cidr : "${var.my_ip_cidr}/32"
}
