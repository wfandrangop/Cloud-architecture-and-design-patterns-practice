output "api_gateway_url" {
  description = "Endpoint publico de la API (prueba: <url>/api/products)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "legacy_private_ip" {
  value = aws_instance.legacy.private_ip
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "alb_internal_dns" {
  value = aws_lb.app.dns_name
}

output "hub_transit_nlb_dns" {
  value = aws_lb.legacy_transit.dns_name
}

output "ecr_java_url" {
  value = aws_ecr_repository.java.repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_java_service" {
  value = aws_ecs_service.java.name
}

output "ecs_frontend_service" {
  value = aws_ecs_service.frontend.name
}

output "lambda_name" {
  value = aws_lambda_function.receipt.function_name
}

output "ssh_bastion" {
  value = "ssh -i labsuser.pem ec2-user@${aws_instance.bastion.public_ip}"
}

output "ssh_legacy_via_bastion" {
  value = "ssh -i labsuser.pem -o ProxyCommand=\"ssh -i labsuser.pem -W %h:%p ec2-user@${aws_instance.bastion.public_ip}\" ec2-user@${aws_instance.legacy.private_ip}"
}

output "rds_tunnel_via_bastion" {
  value = "ssh -i labsuser.pem -N -L 3307:${aws_db_instance.main.address}:3306 ec2-user@${aws_instance.bastion.public_ip}"
}
