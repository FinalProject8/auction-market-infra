# --- 보안 그룹 (Security Groups) ---

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
  description = "ECS Tasks Security Group"
  vpc_id      = aws_vpc.main.id

  # Ingress from ALB
  ingress {
    description     = "Allow traffic from ALB on app port"
    protocol        = "tcp"
    from_port       = 8080 # 앱 포트
    to_port         = 8080
    security_groups = [aws_security_group.alb.id] # ALB SG 참조
  }

  # Egress Rules
  egress { # To RDS (대상 보안 그룹 지정)
    description     = "Allow outbound traffic to RDS MySQL"
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.rds.id] # RDS SG 참조 (이 방향은 여기에 정의)
  }
  egress { # To OpenSearch (대상 보안 그룹 지정)
    description     = "Allow outbound traffic to OpenSearch"
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.opensearch.id] # OpenSearch SG 참조 (이 방향은 여기에 정의)
  }
  egress { # To Internet (HTTPS)
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

# RDS <- ECS 인바운드 허용 규칙
resource "aws_security_group_rule" "rds_from_ecs_ingress" {
  type                     = "ingress"                       # 인바운드 규칙
  security_group_id        = aws_security_group.rds.id     # 이 규칙이 적용될 대상 SG (RDS SG)
  description              = "Allow MySQL traffic from ECS tasks"
  protocol                 = "tcp"
  from_port                = 3306
  to_port                  = 3306
  source_security_group_id = aws_security_group.ecs_tasks.id # 출발지 SG (ECS SG)
}

# OpenSearch <- ECS 인바운드 허용 규칙
resource "aws_security_group_rule" "opensearch_from_ecs_ingress" {
  type                     = "ingress"                       # 인바운드 규칙
  security_group_id        = aws_security_group.opensearch.id# 이 규칙이 적용될 대상 SG (OpenSearch SG)
  description              = "Allow HTTPS traffic from ECS tasks for logs"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.ecs_tasks.id # 출발지 SG (ECS SG)
}