# --- 보안 그룹 (Security Groups) ---
# 새로운 아키텍처 구성 요소들(Redis, Logstash EC2, Prometheus EC2, Lambda, S3, cloud map 통신 허용

# 1. ALB 보안 그룹
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB Security Group"
  vpc_id      = aws_vpc.main.id # vpc.tf의 aws_vpc.main 참조

  ingress {
    description = "Allow HTTP from anywhere"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTPS from anywhere"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

# 2. ECS Task 보안 그룹 (RDS/OS 로의 Egress 규칙 포함)
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks (app1, app2, batch, log_router)"
  vpc_id      = aws_vpc.main.id

  # --- Ingress Rules ---
  ingress {
    description     = "Allow traffic from ALB on app1 port"
    protocol        = "tcp"
    from_port       = 8080 # AuctionMarketApp 포트
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Allow traffic from ALB on app2 port"
    protocol        = "tcp"
    from_port       = 8081 # WebSocketApp 포트
    to_port         = 8081
    security_groups = [aws_security_group.alb.id]
  }

  # prometheus 설정
  ingress {
    description     = "Allow Prometheus scrape from Prometheus EC2 instance"
    protocol        = "tcp"
    # --- 사용자 확인 필요: AuctionMarketApp이 메트릭을 노출하는 포트 ---
    from_port       = 9090
    to_port         = 9090
    security_groups = ["sg-0793bd90ee54ed329"]
  }

  # --- ADDED: ECS Task 간 통신 허용 (예: AuctionMarket -> WebSocket) ---
  ingress {
    description = "Allow traffic from other tasks within the same security group"
    protocol    = "-1" # 모든 프로토콜 또는 필요한 포트(예: 8081)만 지정
    from_port   = 0
    to_port     = 0
    self        = true # 자기 자신 보안 그룹으로부터의 모든 트래픽 허용
  }

  # --- Egress Rules ---
  egress { # To RDS
    description     = "Allow outbound traffic to RDS MySQL"
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.rds.id]
  }
  egress { # To OpenSearch
    description     = "Allow outbound traffic to OpenSearch"
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.opensearch.id]
  }
  # --- ADDED: Egress to Redis ---
  egress {
    description     = "Allow outbound traffic to ElastiCache Redis"
    protocol        = "tcp"
    from_port       = 6379 # Redis 기본 포트
    to_port         = 6379
    security_groups = [aws_security_group.redis.id] # 이전에 정의한 Redis SG 참조
  }
  # --- ADDED: Egress to Logstash EC2 ---
  egress {
    description     = "Allow outbound traffic to Logstash EC2"
    protocol        = "tcp"
    from_port       = 5044
    to_port         = 5044
    security_groups = ["sg-018155e7f006691e7"]
    # cidr_blocks     = ["172.31.12.6/32"]
  }
  egress { # To Internet (HTTPS - ECR, Secrets Manager, S3, GCP 등)
    description = "Allow outbound HTTPS to internet"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress { # DNS TCP
    description = "Allow outbound DNS TCP"
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  egress { # DNS UDP
    description = "Allow outbound DNS UDP"
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# --- ADDED: Lambda 실행용 기본 보안 그룹 (추후 구체화) ---
# resource "aws_security_group" "lambda_exec_sg" {
#   name        = "${var.project_name}-lambda-exec-sg"
#   description = "Security group for Lambda function execution"
#   vpc_id      = aws_vpc.main.id
#
#   # Lambda는 주로 외부로 나가는(Egress) 연결을 하므로, 기본 아웃바운드 허용 유지
#   egress {
#     protocol    = "-1"
#     from_port   = 0
#     to_port     = 0
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   # 인바운드는 필요시 정의 (예: API Gateway 트리거 시)
#
#   tags = { Name = "${var.project_name}-lambda-exec-sg" }
# }

# 3. RDS 보안 그룹 (ECS 로부터의 Ingress 규칙은 별도 정의)
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS Security Group"
  vpc_id      = aws_vpc.main.id

  # Ingress rule from ECS will be defined separately below to break cycle
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-rds-sg" }
}

# 4. OpenSearch 보안 그룹 (ECS 로부터의 Ingress 규칙은 별도 정의)
resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-sg"
  description = "OpenSearch Security Group"
  vpc_id      = aws_vpc.main.id

  # Ingress rule from ECS will be defined separately below to break cycle
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-opensearch-sg" }
}

# --- 순환 종속성 방지를 위해 분리된 보안 그룹 규칙 ---
# (ECS -> RDS/OS Egress는 위 ECS 그룹 내부에 정의, RDS/OS <- ECS Ingress만 분리)
resource "aws_security_group_rule" "rds_from_ecs_ingress" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  description              = "Allow MySQL traffic from ECS tasks"
  protocol                 = "tcp"
  from_port                = 3306
  to_port                  = 3306
  source_security_group_id = aws_security_group.ecs_tasks.id
}

# OpenSearch <- ECS 인바운드 허용 규칙 (유지)
resource "aws_security_group_rule" "opensearch_from_ecs_ingress" {
  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch.id
  description              = "Allow HTTPS traffic from ECS tasks for logs"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.ecs_tasks.id
}

# # --- ADDED: RDS <- Lambda 인바운드 허용 규칙 ---
# resource "aws_security_group_rule" "rds_from_lambda_ingress" {
#   type                     = "ingress"                         # 인바운드 규칙
#   security_group_id        = aws_security_group.rds.id       # 대상: RDS 보안 그룹
#   description              = "Allow MySQL traffic from Lambda function"
#   protocol                 = "tcp"
#   from_port                = 3306
#   to_port                  = 3306
#   source_security_group_id = aws_security_group.lambda_exec_sg.id # 출발지: 위에서 정의한 Lambda 보안 그룹
# }

# redis
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = aws_vpc.main.id

  # 기본 아웃바운드 (모두 허용)
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-redis-sg" }
}

resource "aws_security_group_rule" "redis_from_ecs_ingress" {
  type                     = "ingress"                       # 인바운드 규칙
  security_group_id        = aws_security_group.redis.id     # 대상: Redis 보안 그룹
  description              = "Allow Redis traffic from ECS tasks"
  protocol                 = "tcp"
  from_port                = 6379
  to_port                  = 6379
  source_security_group_id = aws_security_group.ecs_tasks.id # 출발지: ECS 보안 그룹
}

