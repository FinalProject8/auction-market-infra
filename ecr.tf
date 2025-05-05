# --- ECR (Elastic Container Registry) ---

resource "aws_ecr_repository" "app1" {
  name = "my-auction-app" # 실제 사용할 ECR 리포지토리 이름
  tags = { Name = "${var.project_name}-ecr-app1" }
  force_delete = true  # <--- 이 줄 추가
}

resource "aws_ecr_repository" "websocket_app" {
  name = "websocket-app" # WebSocket 앱 ECR 리포지토리 이름
  tags = { Name = "${var.project_name}-ecr-websocket" }
  force_delete = true # 필요시 추가
}

resource "aws_ecr_repository" "batch_app" {
  name = "spring-batch-app" # Batch 앱 ECR 리포지토리 이름
  tags = { Name = "${var.project_name}-ecr-batch" }
  force_delete = true # 필요시 추가
}