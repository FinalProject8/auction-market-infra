resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet-group"
  # Private 서브넷 ID 목록 참조 (vpc.tf 에 정의된 리소스 사용)
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis-cluster" # 클러스터 ID
  engine               = "redis"                            # 엔진 타입
  engine_version       = "7.0"                              # 원하는 Redis 엔진 버전 선택
  node_type            = "cache.t3.micro"                   # 노드 인스턴스 타입 (테스트용 작은 타입)
  num_cache_nodes      = 1                                  # 클러스터 내 노드 개수 (테스트용 1개)
  parameter_group_name = "default.redis7"                  # 파라미터 그룹 (기본값 사용)
  subnet_group_name    = aws_elasticache_subnet_group.redis.name # 위에서 정의한 서브넷 그룹 이름 참조
  security_group_ids   = [aws_security_group.redis.id]      # 위에서 정의한 Redis 보안 그룹 ID 참조

  tags = {
    Name = "${var.project_name}-redis-cluster"
  }
}

