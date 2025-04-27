# --- ECS (Elastic Container Service) ---

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  tags = { Name = "${var.project_name}-cluster" }
}

# ECS Task 실행 역할 (ECR 이미지 가져오기, CloudWatch Logs 전송 등)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task 역할 (애플리케이션이 AWS 서비스 접근 시 필요 - 예: Secrets Manager)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Secrets Manager 읽기 권한 정책 연결 (예시)
resource "aws_iam_policy" "secrets_manager_read_policy" {
  name        = "${var.project_name}-secrets-manager-read-policy"
  description = "Allow reading specific secrets"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # 만약 Secrets Manager가 KMS로 암호화된 경우
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.db_password.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_secrets_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.secrets_manager_read_policy.arn
}


# ECS Task Definition (App1, App2, FireLens Log Router)
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024" # 1 vCPU
  memory                   = "2048" # 2 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn # Secrets Manager 접근 등에 필요

  container_definitions = jsonencode([
    # App1 컨테이너
    {
      name      = "spring-app-1"
      image     = var.app1_image_uri
      cpu       = 512
      memory    = 1024 # App1 메모리 (MiB)
      essential = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }]
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "AWS_REGION", value = var.aws_region }
      ]
      secrets = [ # 비밀번호는 Secrets Manager에서 주입
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = { # FireLens 통해 OpenSearch로 로그 전송
        logDriver = "awsfirelens"
        options = {
          Name              = "opensearch",
          Host              = replace(aws_opensearch_domain.logs.endpoint, "https://", ""),
          Port              = "443",
          Index             = "app1-logs-${formatdate("YYYY-MM-DD", timestamp())}", # 인덱스 이름 (날짜별)
          Type              = "_doc",
          tls               = "On",
          tls.verify        = "Off", # 운영 시 On 권장
          AWS_Auth          = "On",
          AWS_Region        = var.aws_region,
          Retry_Limit       = "3",
          Suppress_Type_Name= "On"
        }
      }
    },
    # App2 컨테이너
    {
      name      = "spring-app-2"
      image     = var.app2_image_uri
      cpu       = 512
      memory    = 1024 # App2 메모리 (MiB)
      essential = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }] # App2도 8080 가정
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "AWS_REGION", value = var.aws_region }
      ]
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = { # FireLens 통해 OpenSearch로 로그 전송
        logDriver = "awsfirelens"
        options = {
          Name              = "opensearch",
          Host              = replace(aws_opensearch_domain.logs.endpoint, "https://", ""),
          Port              = "443",
          Index             = "app2-logs-${formatdate("YYYY-MM-DD", timestamp())}", # 인덱스 이름 (날짜별)
          Type              = "_doc",
          tls               = "On",
          tls.verify        = "Off", # 운영 시 On 권장
          AWS_Auth          = "On",
          AWS_Region        = var.aws_region,
          Retry_Limit       = "3",
          Suppress_Type_Name= "On"
        }
      }
    },
    # FireLens 로그 라우터 컨테이너 (Fluent Bit)
    {
      name      = "log_router"
      image     = "amazon/aws-for-fluent-bit:latest"
      essential = true
      firelensConfiguration = {
        type = "fluentbit"
        options = { enable-ecs-log-metadata = "true" }
      }
      logConfiguration = { # 로그 라우터 자체 로그는 CloudWatch로
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}/log-router",
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "firelens"
        }
      }
      memoryReservation = 50 # 최소 메모리
      user = "0"
    }
  ])

  tags = { Name = "${var.project_name}-app-task" }
}


# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2 # Task 개수 (예: AZ당 1개)
  launch_type     = "FARGATE"

  network_configuration {
    # Public/Private 서브넷 중 선택하여 배치
    subnets         = [for subnet in aws_subnet.public : subnet.id] # 예: Public 서브넷 사용
    security_groups = [aws_security_group.ecs_tasks.id] # ECS Task 보안 그룹
    assign_public_ip = true # Public 서브넷 사용 시 true
  }

  # ALB 연동 설정 (App1, App2 모두 동일 Target Group 사용 시)
  # 만약 Target Group을 분리했다면, load_balancer 블록을 각각 추가해야 합니다.
  load_balancer {
    target_group_arn = aws_lb_target_group.app1.arn # 예: App1 TG 사용
    container_name   = "spring-app-1" # ALB가 연결될 컨테이너 이름
    container_port   = 8080          # 컨테이너 포트
  }
  load_balancer { # App2 용 연결 (만약 App2 TG가 다르다면 수정)
    target_group_arn = aws_lb_target_group.app2.arn # 예: App2 TG 사용
    container_name   = "spring-app-2"
    container_port   = 8080
  }

  # 배포 전략 등 추가 설정 가능
  # deployment_controller { type = "ECS" }

  depends_on = [aws_lb_listener.http] # ALB 리스너 생성 후 서비스 시작

  tags = { Name = "${var.project_name}-service" }
}