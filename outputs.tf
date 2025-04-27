# --- 결과 출력 ---

output "alb_dns_name" {
  description = "ALB의 DNS 이름"
  value       = aws_lb.main.dns_name
}

output "rds_instance_endpoint" {
  description = "RDS MySQL 인스턴스 엔드포인트"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "opensearch_domain_endpoint" {
  description = "OpenSearch 도메인 엔드포인트"
  value       = aws_opensearch_domain.logs.endpoint
}

output "app1_ecr_repository_url" {
  description = "App1 ECR 리포지토리 URL"
  value       = aws_ecr_repository.app1.repository_url
}

output "app2_ecr_repository_url" {
  description = "App2 ECR 리포지토리 URL"
  value       = aws_ecr_repository.app2.repository_url
}

output "db_password_secret_arn" {
  description = "RDS 비밀번호가 저장된 Secrets Manager ARN"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = true
}