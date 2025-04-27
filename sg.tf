# --- 보안 그룹 (Security Groups) ---

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB Security Group"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "ECS Tasks Security Group"
  vpc_id      = aws_vpc.main.id

  # ALB로부터의 인바운드 (App1/App2: 8080 가정)
  ingress {
    protocol                 = "tcp"
    from_port                = 8080
    to_port                  = 8080
    source_security_group_id = aws_security_group.alb.id
  }
  # 아웃바운드 규칙: RDS, OpenSearch, 인터넷(ECR, AWS API 등) 접근 허용
  egress { # To RDS
    protocol                 = "tcp"
    from_port                = 3306
    to_port                  = 3306
    source_security_group_id = aws_security_group.rds.id # 아래 정의된 RDS SG 참조
  }
  egress { # To OpenSearch
    protocol                 = "tcp"
    from_port                = 443
    to_port                  = 443
    source_security_group_id = aws_security_group.opensearch.id # 아래 정의된 OS SG 참조
  }
  egress { # To Internet (HTTPS)
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  # DNS 접근 (필요 시)
  egress {
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [aws_vpc.main.cidr_block] # VPC 내부 DNS
  }
  egress {
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS Security Group"
  vpc_id      = aws_vpc.main.id

  # ECS Tasks 로부터의 인바운드 (MySQL 포트)
  ingress {
    protocol                 = "tcp"
    from_port                = 3306
    to_port                  = 3306
    source_security_group_id = aws_security_group.ecs_tasks.id
  }
  # 기본 아웃바운드는 보통 허용되지만 명시적으로 추가 가능
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-rds-sg" }
}

resource "aws_security_group" "opensearch" {
  name        = "${var.project_name}-opensearch-sg"
  description = "OpenSearch Security Group"
  vpc_id      = aws_vpc.main.id

  # ECS Tasks 로부터의 인바운드 (HTTPS)
  ingress {
    protocol                 = "tcp"
    from_port                = 443
    to_port                  = 443
    source_security_group_id = aws_security_group.ecs_tasks.id
  }
  # 기본 아웃바운드는 보통 허용되지만 명시적으로 추가 가능
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-opensearch-sg" }
}