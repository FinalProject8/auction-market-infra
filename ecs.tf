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
          "kms:Decrypt" # Secrets Manager가 KMS로 암호화된 경우
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.db_password.arn # rds.tf 에서 정의된 secret 참조
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_secrets_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.secrets_manager_read_policy.arn
}


# ECS Task Definition (App1, App2, FireLens Log Router)
# !!! container_definitions 는 이 resource 블록 내부에 위치해야 합니다 !!!
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024" # 예: 1 vCPU
  memory                   = "2048" # 예: 2 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn # Secrets Manager 접근 등에 필요

  # --- 컨테이너 정의 ---
  container_definitions = jsonencode([
    # App1 컨테이너
    {
      name      = "spring-app-1"
      image     = var.app1_image_uri # variables.tf 에서 정의
      cpu       = 512 # 할당 CPU (전체 CPU 내에서)
      memory    = 1024 # 할당 메모리 MiB (전체 메모리 내에서)
      essential = true
      portMappings = [{ containerPort = 8080}] # 앱 포트
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" }, # rds.tf 리소스 참조
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username }, # variables.tf 참조
        { name = "AWS_REGION", value = var.aws_region } # variables.tf 참조
      ]
      secrets = [ # 비밀번호는 Secrets Manager에서 주입 (rds.tf 리소스 참조)
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = { # FireLens 통해 OpenSearch로 로그 전송
        logDriver = "awsfirelens"
        options = {
          Name              = "opensearch",
          Host              = replace(aws_opensearch_domain.logs.endpoint, "https://", ""), # opensearch.tf 리소스 참조
          Port              = "443",
          Index             = "app1-logs-${formatdate("YYYY-MM-DD", timestamp())}", # 인덱스 이름 (날짜별 자동 생성)
          Type              = "_doc",
          tls               = "On",
          "tls.verify"      = "Off",  # <--- 키 이름을 따옴표로 감싸서 수정됨
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
      image     = var.app2_image_uri # variables.tf 에서 정의
      cpu       = 512 # 할당 CPU
      memory    = 1024 # 할당 메모리 MiB
      essential = true
      portMappings = [{ containerPort = 8081}] # App2도 8080 사용 가정
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" }, # rds.tf 리소스 참조
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username }, # variables.tf 참조
        { name = "AWS_REGION", value = var.aws_region } # variables.tf 참조
      ]
      secrets = [ # 비밀번호는 Secrets Manager에서 주입 (rds.tf 리소스 참조)
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = { # FireLens 통해 OpenSearch로 로그 전송
        logDriver = "awsfirelens"
        options = {
          Name              = "opensearch",
          Host              = replace(aws_opensearch_domain.logs.endpoint, "https://", ""), # opensearch.tf 리소스 참조
          Port              = "443",
          Index             = "app2-logs-${formatdate("YYYY-MM-DD", timestamp())}", # 인덱스 이름 (날짜별 자동 생성)
          Type              = "_doc",
          tls               = "On",
          "tls.verify"      = "Off",  # <--- 키 이름을 따옴표로 감싸서 수정됨
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
      image     = "amazon/aws-for-fluent-bit:latest" # AWS 제공 이미지
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
          "awslogs-stream-prefix" = "firelens" # 스트림 접두사
        }
      }
      memoryReservation = 50 # 최소 메모리 (MiB)
      user = "0" # root 권한으로 실행 (필요시)
    }
  ]) # container_definitions jsonencode 끝

  tags = { Name = "${var.project_name}-app-task" }

} # aws_ecs_task_definition "app" 리소스 블록 끝


# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2 # 실행할 Task 개수 (예: 가용 영역당 1개)
  launch_type     = "FARGATE"

  network_configuration {
    # Public 또는 Private 서브넷 중 선택하여 배치 가능
    subnets         = [for subnet in aws_subnet.public : subnet.id] # 예: Public 서브넷 사용 (vpc.tf 참조)
    security_groups = [aws_security_group.ecs_tasks.id] # ECS Task 보안 그룹 (sg.tf 참조)
    assign_public_ip = true # Public 서브넷 사용 시 Public IP 자동 할당 여부
  }

  # ALB 연동 설정
  load_balancer {
    target_group_arn = aws_lb_target_group.app1.arn # App1 타겟 그룹 연결 (alb.tf 참조)
    container_name   = "spring-app-1" # Task Definition 내의 App1 컨테이너 이름
    container_port   = 8080          # App1 컨테이너 포트
  }
  load_balancer { # App2 용 연결
    target_group_arn = aws_lb_target_group.app2.arn # App2 타겟 그룹 연결 (alb.tf 참조)
    container_name   = "spring-app-2" # Task Definition 내의 App2 컨테이너 이름
    container_port   = 8081          # App2 컨테이너 포트 (App2도 8080 가정)
  }

  # 서비스 배포 관련 추가 옵션 설정 가능
  # health_check_grace_period_seconds = 60
  # deployment_maximum_percent        = 200
  # deployment_minimum_healthy_percent = 100

  depends_on = [aws_lb_listener.http] # ALB 리스너 생성 후 서비스 시작 (alb.tf 참조)

  tags = { Name = "${var.project_name}-service" }
}