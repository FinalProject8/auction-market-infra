terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # 적절한 버전 명시
    }
  }
  required_version = ">= 1.2.0" # Terraform 버전 명시
}

provider "aws" {
  region = var.aws_region # 변수 사용 (variables.tf 에서 정의)
}

# 사용할 AWS 리전 변수 (variables.tf 에서 정의)
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # 예시 CIDR, 필요시 조정
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# --- Subnets ---
# 가용 영역 2개 사용 (ap-northeast-2a, ap-northeast-2c)
variable "availability_zones" {
  description = "Availability Zones to use"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# Public Subnets (ALB 용)
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index) # 예: 10.0.0.0/24, 10.0.1.0/24
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true # Public IP 자동 할당 (ALB에는 직접적 영향 없음)

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Private Subnets (ECS, RDS, ElastiCache 용)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + length(var.availability_zones)) # 예: 10.0.2.0/24, 10.0.3.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

# --- Gateways & Routing ---
# Internet Gateway (Public Subnet 용)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "main-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway & EIP (Private Subnet 에서 외부 통신용)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "main-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Public Subnet 중 하나에 위치
  tags = { Name = "main-nat-gw" }
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-route-table" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security Groups ---
# ALB Security Group (외부에서 HTTP/HTTPS 접근 허용)
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow HTTP/HTTPS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress { # HTTPS 사용 시
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "alb-sg" }
}

# ECS Tasks Security Group (ALB 로부터 8080 포트 허용, 외부 통신 허용)
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Allow inbound traffic from ALB and outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080 # 애플리케이션 포트
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # ALB SG 로부터의 접근만 허용
  }
  # 필요 시 다른 서비스(WebSocket -> Auction) 간 통신 규칙 추가
  # ingress {
  #   from_port       = 8080
  #   to_port         = 8080
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.ecs_tasks.id] # 자기 자신 허용 (ECS 서비스 간 통신)
  # }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    cidr_blocks = ["0.0.0.0/0"] # 외부 통신 허용 (ECR, 외부 API 등)
  }
  tags = { Name = "ecs-tasks-sg" }
}

# RDS MySQL Security Group (ECS Tasks SG 로부터 3306 포트 허용)
resource "aws_security_group" "rds_mysql" {
  name        = "rds-mysql-sg"
  description = "Allow inbound traffic from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id] # ECS Tasks SG 로부터의 접근만 허용
  }
  egress { # 일반적으로 필요 없음
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "rds-mysql-sg" }
}

# ElastiCache Redis Security Group (ECS Tasks SG 로부터 6379 포트 허용)
resource "aws_security_group" "elasticache_redis" {
  name        = "elasticache-redis-sg"
  description = "Allow inbound traffic from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id] # ECS Tasks SG 로부터의 접근만 허용
  }
  egress { # 일반적으로 필요 없음
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "elasticache-redis-sg" }
}
# terraform/main.tf (이어서)

# --- RDS for MySQL ---
# RDS Subnet Group (Private Subnets 사용)
resource "aws_db_subnet_group" "rds" {
  name       = "rds-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags = { Name = "rds-subnet-group" }
}

# Secrets Manager 에서 DB 비밀번호 관리
resource "aws_secretsmanager_secret" "db_password" {
  name = "db-password-secret" # Secret 이름
  # 실제 비밀번호 값은 Terraform 코드에 넣지 않고,
  # 초기 배포 후 AWS 콘솔이나 CLI를 통해 안전하게 입력합니다.
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier           = "main-mysql-db"
  allocated_storage    = 20 # 스토리지 (GB)
  storage_type         = "gp3"
  engine               = "mysql"
  engine_version       = "8.0" # 사용할 MySQL 버전
  instance_class       = "db.t3.micro" # 인스턴스 타입 (프리티어 또는 저렴한 옵션)
  db_name              = "auction_db" # 초기 데이터베이스 이름 (옵션)
  username             = "admin"      # 마스터 사용자 이름
  password             = aws_secretsmanager_secret_version.db_password_val.secret_string # Secrets Manager 에서 가져옴
  db_subnet_group_name = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds_mysql.id]
  skip_final_snapshot  = true # 테스트 환경에서는 true, 운영 환경에서는 false 고려
  multi_az             = false # 개발/테스트는 false, 운영은 true 고려
  # 백업, 파라미터 그룹 등 추가 설정 가능

  tags = { Name = "main-mysql-db" }

  # Secret 값이 설정된 후에 DB 인스턴스 생성하도록 의존성 명시
  depends_on = [aws_secretsmanager_secret_version.db_password_val]
}

# Secret 값 조회를 위한 데이터 소스 (초기 생성 시에는 비어있을 수 있음)
# 주의: Secret에 값이 설정되기 전에는 에러 발생 가능.
# 초기 배포 시에는 password 를 직접 지정하고, 이후 Secret에서 읽도록 변경하거나
# depends_on 으로 순서 제어 필요. 아래는 값이 이미 있다고 가정.
data "aws_secretsmanager_secret_version" "db_password_val" {
  secret_id = aws_secretsmanager_secret.db_password.id
}
# terraform/main.tf (이어서)

# --- ElastiCache for Redis ---
# ElastiCache Subnet Group (Private Subnets 사용)
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
  tags = { Name = "redis-subnet-group" }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "main-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro" # 인스턴스 타입
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7" # 사용할 Redis 버전 파라미터 그룹
  engine_version       = "7.x" # 사용할 Redis 버전 (parameter_group_name과 일치)
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.elasticache_redis.id]
  # 백업, 유지보수 윈도우 등 추가 설정 가능

  tags = { Name = "main-redis-cluster" }
}

# terraform/main.tf (이어서)

# --- ECR Repositories ---
variable "app_names" {
  description = "List of application names"
  type        = list(string)
  default     = ["auction", "websocket", "app3", "app4"] # 실제 앱 이름으로 변경
}

resource "aws_ecr_repository" "app_repo" {
  count = length(var.app_names)
  name  = "${var.app_names[count.index]}-app-repo" # 예: auction-app-repo

  image_tag_mutability = "MUTABLE" # 태그 변경 가능 (latest 등 사용 시) 또는 IMMUTABLE

  image_scanning_configuration {
    scan_on_push = true # 이미지 푸시 시 취약점 스캔 활성화
  }

  tags = {
    Name        = "${var.app_names[count.index]}-app-repo"
    Application = var.app_names[count.index]
  }
}
# terraform/main.tf (이어서)

# --- Secrets Manager for JWT Key ---
resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "jwt-secret-key" # Secret 이름
  # 실제 값은 초기 배포 후 AWS 콘솔 등에서 안전하게 입력
}

# 필요시 Secret 값 조회를 위한 데이터 소스 (값이 이미 있다고 가정)
data "aws_secretsmanager_secret_version" "jwt_secret_val" {
  secret_id = aws_secretsmanager_secret.jwt_secret.id
}
# terraform/main.tf (이어서)

# --- Application Load Balancer (ALB) ---
resource "aws_lb" "main" {
  name               = "main-alb"
  internal           = false # 외부용 ALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false # 운영 환경에서는 true 고려

  tags = { Name = "main-alb" }
}

# Target Group (예: 경매 앱용)
resource "aws_lb_target_group" "auction_app" {
  name        = "auction-app-tg"
  port        = 8080 # 컨테이너 포트
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate 사용 시 'ip'

  health_check {
    enabled             = true
    path                = "/actuator/health" # Spring Boot Actuator health check 경로 (의존성 추가 필요)
    protocol            = "HTTP"
    matcher             = "200" # 정상 응답 코드
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "auction-app-tg" }
}

# Target Group (예: 웹소켓 앱용 - 필요 시)
resource "aws_lb_target_group" "websocket_app" {
  name        = "websocket-app-tg"
  port        = 8081 # 웹소켓 앱 포트 (예시)
  protocol    = "HTTP" # WebSocket은 HTTP/HTTPS 위에서 동작
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health" # 각 앱의 health check 경로
    protocol            = "HTTP"
    # ... (auction_app 과 유사하게 설정)
  }

  tags = { Name = "websocket-app-tg" }
}
# ... 필요 시 app3, app4 용 Target Group 추가 ...

# ALB Listener (HTTP:80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auction_app.arn # 기본 타겟 그룹 (예: 경매 앱)
  }
}

# Listener Rule (경로 기반 라우팅 예시)
# resource "aws_lb_listener_rule" "websocket_rule" {
#   listener_arn = aws_lb_listener.http.arn
#   priority     = 10 # 우선순위 (낮을수록 높음)
#
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.websocket_app.arn
#   }
#
#   condition {
#     path_pattern {
#       values = ["/websocket/*"] # 웹소켓 관련 경로
#     }
#   }
# }
# ... 필요 시 app3, app4 용 Listener Rule 추가 ...

# terraform/main.tf (이어서)

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "main-cluster"
  tags = { Name = "main-cluster" }
}

# --- CloudWatch Log Group (ECS 로그 저장용) ---
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/main-cluster-logs"
  retention_in_days = 7 # 로그 보관 기간 (조정 가능)
  tags = { Name = "ecs-log-group" }
}

# --- ECS Task Definitions & Services (앱 개수만큼 반복) ---

# 예시: 경매 앱 (auction)
resource "aws_ecs_task_definition" "auction_app" {
  family                   = "auction-app-task"
  network_mode             = "awsvpc" # Fargate 필수
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU (최소 단위부터 시작)
  memory                   = "512"  # 512 MiB (최소 단위부터 시작)
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn # 아래에서 정의할 실행 역할
  task_role_arn            = aws_iam_role.ecs_task_role.arn # (선택적) 컨테이너가 다른 AWS 서비스 접근 시 필요

  # 컨테이너 정의 (JSON 형식)
  container_definitions = jsonencode([
    {
      name      = "auction-app-container"
      image     = "${aws_ecr_repository.app_repo[0].repository_url}:latest" # CI/CD 에서 업데이트할 이미지 URI (초기엔 latest, 이후 commit SHA 등)
      essential = true
      portMappings = [
        {
          containerPort = 8080 # 애플리케이션 포트
          hostPort      = 8080 # awsvpc 모드에서는 동일하게 설정
          protocol      = "tcp"
        }
      ]
      # 환경 변수 주입
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" }, # 예: 운영 프로파일 활성화
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.mysql.address}:${aws_db_instance.mysql.port}/${aws_db_instance.mysql.db_name}?serverTimezone=UTC&useSSL=false" }, # RDS 엔드포인트 주입
        { name = "SPRING_DATASOURCE_USERNAME", value = aws_db_instance.mysql.username },
        { name = "SPRING_REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address }, # Redis 엔드포인트 주입
        { name = "SPRING_REDIS_PORT", value = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port) },
        # 웹소켓 서비스 주소 (ALB 내부 DNS 또는 서비스 디스커버리 사용 - 여기서는 예시로 ALB 사용)
        { name = "WEBSOCKET_SERVER_URL", value = "http://${aws_lb.main.dns_name}" } # 필요 시 경로 추가
      ]
      # Secret 주입 (Secrets Manager 값)
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "JWT_SECRET_KEY", valueFrom = aws_secretsmanager_secret.jwt_secret.arn }
      ]
      # 로그 설정 (CloudWatch Logs)
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "auction-app" # 로그 스트림 접두사
        }
      }
    }
  ])

  tags = { Name = "auction-app-task" }
}

resource "aws_ecs_service" "auction_app" {
  name            = "auction-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auction_app.arn
  desired_count   = 1 # 실행할 컨테이너 개수 (조정 가능)
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [for subnet in aws_subnet.private : subnet.id] # Private Subnet 에 배포
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # Private Subnet 이므로 false
  }

  # ALB 와 연결
  load_balancer {
    target_group_arn = aws_lb_target_group.auction_app.arn
    container_name   = "auction-app-container" # Task Definition 에 정의된 컨테이너 이름
    container_port   = 8080 # 컨테이너 포트
  }

  # 서비스가 Task Definition 변경을 감지하고 배포하도록 설정
  deployment_controller {
    type = "ECS" # Rolling Update (기본값)
  }

  # ALB Target Group 등록이 완료될 때까지 기다림
  depends_on = [aws_lb_listener.http]

  tags = { Name = "auction-app-service" }
}


# --- ECS Task Execution Role (필수) ---
# ECS 에이전트가 ECR 이미지 풀링, CloudWatch 로그 전송 등을 위해 필요한 권한
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  tags = { Name = "ecs-task-execution-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Role (선택적) ---
# 컨테이너 내 애플리케이션이 다른 AWS 서비스(S3, SQS 등)에 접근해야 할 경우 필요한 권한
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  tags = { Name = "ecs-task-role" }
}

# 예시: S3 접근 권한 부여 (필요 시 정책 추가)
# resource "aws_iam_role_policy" "ecs_task_s3_policy" {
#   name = "ecs-task-s3-policy"
#   role = aws_iam_role.ecs_task_role.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = ["s3:GetObject", "s3:PutObject"]
#         Effect   = "Allow"
#         Resource = "arn:aws:s3:::<your-bucket-name>/*"
#       }
#     ]
#   })
# }


# --- 웹소켓 앱, app3, app4 에 대해서도 위 Task Definition 과 Service 리소스를 유사하게 정의 ---
# - family, container_definitions.name, image, environment, secrets, logConfiguration.options.awslogs-stream-prefix 등 수정
# - service.name, task_definition, load_balancer (필요 시), tags 등 수정
# - 웹소켓 앱의 경우 포트(예: 8081)가 다르면 Task Definition, Service, Target Group 등에서 해당 포트로 수정
# - ALB에 연결하지 않는 내부 서비스의 경우 Service 에서 load_balancer 블록 제외