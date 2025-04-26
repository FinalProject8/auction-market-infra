# terraform/outputs.tf

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_urls" {
  description = "URLs of the ECR repositories"
  value       = { for i, repo in aws_ecr_repository.app_repo : var.app_names[i] => repo.repository_url }
}

output "rds_instance_endpoint" {
  description = "Endpoint address of the RDS MySQL instance"
  value       = aws_db_instance.mysql.address
  sensitive   = true # 민감 정보일 수 있으므로 마스킹 처리
}

output "redis_cluster_endpoint" {
  description = "Endpoint address of the ElastiCache Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}