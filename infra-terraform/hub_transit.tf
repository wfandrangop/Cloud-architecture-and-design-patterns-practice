# =============================================================================
# Transito Spoke-App -> Spoke-Legacy a traves del Hub.
#
# Como el VPC Peering no es transitivo, el order-service (10.1.x) no puede llegar
# directamente a 10.2.1.10. Un NLB interno en las subredes de transito del Hub recibe
# la conexion (destino = IP del Hub, permitido por el peering HUB<->APP) y abre una
# conexion nueva hacia 10.2.1.10:8081 (permitido por el peering HUB<->LEGACY).
#
# preserve_client_ip = false es OBLIGATORIO: asi el legado ve como origen la IP del NLB
# (10.0.x) y responde por el peering Hub. Si viera 10.1.x no tendria ruta de vuelta.
# =============================================================================

resource "aws_lb" "legacy_transit" {
  name                             = "${local.name}-hub-transit-nlb"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = aws_subnet.hub_private[*].id
  enable_cross_zone_load_balancing = true
  tags                             = { Name = "${local.name}-hub-transit-nlb" }
}

resource "aws_lb_target_group" "legacy" {
  name               = "${local.name}-legacy-tg"
  port               = 8081
  protocol           = "TCP"
  target_type        = "ip"
  vpc_id             = aws_vpc.hub.id
  preserve_client_ip = "false"

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "8081"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Destino fuera de la VPC del target group (VPC peered) => availability_zone = "all"
resource "aws_lb_target_group_attachment" "legacy" {
  target_group_arn  = aws_lb_target_group.legacy.arn
  target_id         = var.legacy_private_ip
  port              = 8081
  availability_zone = "all"

  depends_on = [aws_route_table_association.hub_private, aws_route_table_association.legacy_private]
}

resource "aws_lb_listener" "legacy" {
  load_balancer_arn = aws_lb.legacy_transit.arn
  port              = 8081
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.legacy.arn
  }
}
