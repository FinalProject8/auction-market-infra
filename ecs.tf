# --- ECS (Elastic Container Service) ---

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  tags = { Name = "${var.project_name}-cluster" }
}

# ECS Task 실행 역할 (ECR 이미지 가져오기, CloudWatch Logs 전송, Secrets Manager 접근 등)
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

# 기본 Task Execution Role 정책 연결
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Execution Role이 Secrets Manager 비밀번호를 가져올 수 있도록 허용하는 정책
resource "aws_iam_policy" "task_execution_secrets_policy" {
  name        = "${var.project_name}-task-exec-secrets-policy"
  description = "Allow ECS Task Execution Role to fetch specific secrets and decrypt"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowGetSecretValue",
        Action = ["secretsmanager:GetSecretValue"],
        Effect = "Allow",
        # --- rds.tf 및 secrets.tf(GCP용) 에서 정의될 Secret ARN 참조 ---
        # 여러 Secret ARN을 리스트로 지정 가능
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.gcp_key.arn  # GCP 키 Secret 리소스 정의 후 해당 ARN 사용
        ]
      },
      {
        Sid      = "AllowKmsDecrypt",
        Action   = ["kms:Decrypt"],
        Effect   = "Allow",
        Resource = "*" # 기본 KMS 키 사용 가정, 특정 키 사용 시 해당 ARN 지정
      }
    ]
  })
}

# 위에서 생성한 정책을 Task Execution Role에 연결
resource "aws_iam_role_policy_attachment" "task_execution_role_secrets_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.task_execution_secrets_policy.arn
}


# ECS Task 역할 (애플리케이션 코드가 AWS 서비스 접근 시 필요)
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

# Task Role에 대한 Secrets Manager 읽기 권한 정책 (애플리케이션 코드용 - DB 암호)
# ECS Task Role 연결된 정책(modified 05.04)
resource "aws_iam_policy" "ecs_task_role_policy" {
  name        = "${var.project_name}-ecs-task-role-policy"
  description = "Policy for ECS Task Role accessing various AWS services"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowReadDBPasswordSecret",
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # 필요한 경우
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.db_password.arn # rds.tf 에서 정의된 secret 참조
      },
      # --- ADDED: GCP Secret 접근 권한 ---
      {
        Sid    = "AllowReadGCPCredentialsSecret",
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # 필요한 경우
        ],
        Effect   = "Allow",
        # 나중에 GCP 키 저장용 Secret 리소스 생성 후 해당 ARN 사용
        Resource = aws_secretsmanager_secret.gcp_key.arn
      },
      # --- ADDED: Cloud Map 서비스 검색 권한 ---
      {
        Sid    = "AllowDiscoverInstances",
        Action = ["servicediscovery:DiscoverInstances"],
        Effect = "Allow",
        # 특정 네임스페이스나 서비스로 제한하거나, 우선 "*" 사용 가능
        Resource = "*"
      },
      # --- ADDED: S3 버킷 접근 권한 ---
      {
        Sid    = "AllowS3BucketAccess",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
          # 필요한 S3 작업 추가
        ],
        Effect = "Allow",
        # Terraform으로 생성한 S3 버킷 리소스의 ARN과 그 하위 객체들을 참조
        Resource = [
          aws_s3_bucket.product_images.arn,      # 버킷 자체 ARN
          "${aws_s3_bucket.product_images.arn}/*"
        ]
      }
      # Redis 접근 권한 (IAM 인증 사용 시) ---
      # Redis에 IAM 인증을 사용한다면 여기에 elasticache:Connect 권한 추가 필요
      # EventBridge 접근 권한 (Event 생성 시) ---
      # AuctionMarket 앱이 직접 EventBridge 이벤트를 발생시킨다면 events:PutEvents 권한 추가 필요
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_task_role_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_role_policy.arn
}

# --- MODIFIED: ECS Task Definition (3 Apps + FireLens Log Router) ---
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # CPU/Memory 는 3개 앱 + 로그 라우터의 총 요구량을 고려하여 재산정 필요
  cpu                      = "2048" # 예: 2 vCPU (이전보다 증가)
  memory                   = "4096" # 예: 4 GB (이전보다 증가)
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn # Secrets Manager, ECR 접근 권한 등 포함
  task_role_arn            = aws_iam_role.ecs_task_role.arn # App들이 사용할 AWS 권한 (Secrets, S3, CloudMap 등)

  # --- 컨테이너 정의 (3개 앱 + 1개 로그 라우터) ---
  # ecs.tf 파일 -> resource "aws_ecs_task_definition" "app" -> container_definitions 수정

  container_definitions = jsonencode([
    # 1. AuctionMarketApp 컨테이너
    {
      name      = "auction-market-app"
      image     = var.auction_image_uri           # terraform.tfvars 참조
      cpu       = 896                             # 예시값, 조정 필요
      memory    = 1792                            # 예시값, 조정 필요
      essential = true
      portMappings = [{ containerPort = 8080 }]
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" }, # rds.tf, variables.tf 참조
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username }, # variables.tf 참조
        { name = "AWS_REGION", value = var.aws_region },                   # variables.tf 참조
        # --- Placeholders Replaced ---
        { name = "WEBSOCKET_SERVICE_DISCOVERY_NAME", value = "${aws_service_discovery_service.websocket.name}.${aws_service_discovery_private_dns_namespace.internal.name}" }, # cloudmap.tf 참조
        { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address }, # redis.tf 참조 (Cluster Mode 비활성 가정)
        { name = "S3_BUCKET_NAME", value = aws_s3_bucket.product_images.bucket } # s3.tf 참조
      ]
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn } # rds.tf 참조
      ]
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name       = "logstash",
          Host       = var.logstash_host, # variables.tf/tfvars 참조
          Port       = var.logstash_port, # variables.tf/tfvars 참조
          Format     = "json"
          # tls        = "off",           # Logstash TLS 설정 확인 필요
          # tls.verify = "off"
        }
      }
    },
    # 2. WebSocketApp 컨테이너
    {
      name      = "websocket-app"
      image     = var.websocket_app_image_uri # terraform.tfvars 참조
      cpu       = 512                           # 예시값
      memory    = 1024                          # 예시값
      essential = true
      portMappings = [{ containerPort = 8081 }] # WebSocket 포트
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        # { name = "SPRING_DATASOURCE_URL", value = ... }, # DB 필요 시
        # { name = "SPRING_DATASOURCE_USERNAME", value = ... },
        { name = "AWS_REGION", value = var.aws_region },
        # --- Placeholders Replaced ---
        { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address } # redis.tf 참조
      ]
      secrets = [
        # { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn } # DB 필요 시
      ]
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name       = "logstash",
          Host       = var.logstash_host, # variables.tf/tfvars 참조
          Port       = var.logstash_port, # variables.tf/tfvars 참조
          Format     = "json"
          # tls        = "off",
          # tls.verify = "off"
        }
      }
    },
    # 3. SpringBatchApp 컨테이너
    {
      name      = "batch-app"
      image     = var.batch_app_image_uri # terraform.tfvars 참조
      cpu       = 512                     # 예시값
      memory    = 1024                    # 예시값
      essential = true                    # 필요시 false 로 변경 가능
      # portMappings 없음
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${aws_db_instance.main.endpoint}/${var.db_name}" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "AWS_REGION", value = var.aws_region },
        # --- Placeholders Replaced ---
        # GCP Key Secret ARN 참조 (secrets.tf 등 참조). 앱은 이 ARN을 이용해 SDK로 실제 키 값을 가져와야 함.
        { name = "GCP_CREDENTIALS_SECRET_ARN", value = aws_secretsmanager_secret.gcp_key.arn }
      ]
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name       = "logstash",
          Host       = var.logstash_host, # variables.tf/tfvars 참조
          Port       = var.logstash_port, # variables.tf/tfvars 참조
          Format     = "json"
          # tls        = "off",
          # tls.verify = "off"
        }
      }
    },
    # 4. FireLens 로그 라우터 컨테이너 (Fluent Bit)
    {
      name      = "log_router",
      image     = "amazon/aws-for-fluent-bit:latest",
      essential = true,
      firelensConfiguration = {
        type = "fluentbit"
        options = { enable-ecs-log-metadata = "true" }
      },
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          # CloudWatch Log Group 리소스 참조 (cloudwatch.tf 또는 ecs.tf 정의 가정)
          "awslogs-group"         = aws_cloudwatch_log_group.log_router_lg.name,
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "firelens"
        }
      },
      memoryReservation = 128, # 필요시 조정
      user = "0"
    }
  ]) # container_definitions jsonencode 끝# container_definitions jsonencode 끝

  # --- (Optional) Define Volumes if needed (e.g., for Filebeat config/data, not needed for FireLens stdout) ---
  # volume {
  #   name = "my-volume"
  #   host_path = "/ecs/my-volume" # Not applicable for Fargate host path
  #   # Use EFS for persistent shared storage on Fargate if needed
  # }

  tags = { Name = "${var.project_name}-app-task" }

} # aws_ecs_task_definition "app" 리소스 블록 끝


# --- MODIFIED: ECS Service ---
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn # 업데이트된 Task Definition 참조
  desired_count   = 2 # 필요시 조정
  launch_type     = "FARGATE"

  # 배포 중단 및 재시작 시 오래된 Task 종료 대기 시간 증가 (선택 사항)
  # deployment_configuration {
  #   deployment_circuit_breaker {
  #     enable   = true
  #     rollback = true
  #   }
  #   maximum_percent        = 200
  #   minimum_healthy_percent = 100
  # }
  # health_check_grace_period_seconds = 120 # 예: Task 시작 후 상태 검사 유예 시간 증가

  network_configuration {
    subnets         = [for subnet in aws_subnet.public : subnet.id] # 필요시 Private Subnet으로 변경
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true # Private Subnet 사용 시 false
  }

  # ALB 연동 설정 (AuctionMarketApp, WebSocketApp)
  load_balancer {
    target_group_arn = aws_lb_target_group.app1.arn
    container_name   = "auction-market-app" # <--- 컨테이너 이름 변경 반영
    container_port   = 8080
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.app2.arn
    container_name   = "websocket-app" # <--- 컨테이너 이름 변경 반영
    container_port   = 8081 # WebSocket 앱 포트
  }

  # --- ADDED: Cloud Map Service Registry  ---
  service_registries {
    registry_arn = aws_service_discovery_service.websocket.arn
    container_name = "websocket-app" # 컨테이너 지정 가능
    container_port = 8081
  }

  # ALB 리스너 규칙이 먼저 생성되도록 의존성 유지
  depends_on = [aws_lb_listener.http, aws_lb_listener_rule.app2_path] # App2 규칙 리소스 이름 확인 필요

  tags = { Name = "${var.project_name}-service" }
}