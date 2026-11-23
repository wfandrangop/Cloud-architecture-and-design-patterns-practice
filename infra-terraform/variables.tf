variable "aws_region" {
  description = "Region del Learner Lab"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Dos AZ (ALB y RDS exigen al menos 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "project_name" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "ministore"
}

variable "my_ip_cidr" {
  description = "Tu IP publica (p.ej. 181.198.10.20 o 181.198.10.20/32). Unico origen permitido para SSH al Bastion. Si no lleva mascara se asume /32."
  type        = string

  validation {
    condition     = can(cidrhost(strcontains(var.my_ip_cidr, "/") ? var.my_ip_cidr : "${var.my_ip_cidr}/32", 0))
    error_message = "my_ip_cidr debe ser una IP o un CIDR valido, p.ej. 181.198.10.20 o 181.198.10.20/32."
  }
}

variable "key_name" {
  description = "Key pair EC2 para SSH. En el Learner Lab existe 'vockey' (descarga labsuser.pem desde AWS Details)."
  type        = string
  default     = "vockey"
}

variable "legacy_private_ip" {
  description = "IP privada fija de la EC2 Lift-and-Shift (la misma direccion que tenia el servidor on-premise)"
  type        = string
  default     = "10.2.1.10"
}

variable "db_username" {
  description = "Usuario administrador de RDS MySQL"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Password de RDS MySQL (min. 8 caracteres)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password debe tener al menos 8 caracteres."
  }
}

variable "java_image_tag" {
  description = "Tag de la imagen ministore-java en ECR"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Tag de la imagen ministore-react-nginx en ECR"
  type        = string
  default     = "latest"
}

variable "java_desired_count" {
  description = "Tareas Fargate del order-service detras del ALB"
  type        = number
  default     = 2
}

variable "frontend_allowed_cidr" {
  description = "Quien puede abrir el portal React (puerto 80 de la tarea Fargate del frontend)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "api_throttle_rate" {
  description = "API Gateway: peticiones por segundo sostenidas"
  type        = number
  default     = 20
}

variable "api_throttle_burst" {
  description = "API Gateway: rafaga maxima"
  type        = number
  default     = 40
}
