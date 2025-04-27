# --- OpenSearch ---

resource "aws_opensearch_domain" "logs" {
  domain_name    = var.opensearch_domain_name
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1 # 테스트용
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp2"
  }

  vpc_options {
    subnet_ids         = [for subnet in aws_subnet.private : subnet.id] # Private 서브넷 사용
    security_group_ids = [aws_security_group.opensearch.id] # OpenSearch 보안 그룹 연결
  }

  access_policies = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "*" # 실제로는 특정 IAM 역할 ARN 등으로 제한 필요
        },
        Action = "es:*",
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain_name}/*"
      }
    ]
  })

  # 운영 환경에서는 Cognito 인증 또는 세분화된 접근 제어 추가 고려

  tags = {
    Name = "${var.project_name}-opensearch"
  }
}