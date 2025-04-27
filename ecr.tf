# --- ECR (Elastic Container Registry) ---

resource "aws_ecr_repository" "app1" {
  name = "auction-market-app" # 실제 사용할 ECR 리포지토리 이름
  tags = { Name = "${var.project_name}-ecr-app1" }
}

resource "aws_ecr_repository" "app2" {
  name = "auction-market-realtime" # 실제 사용할 ECR 리포지토리 이름
  tags = { Name = "${var.project_name}-ecr-app2" }
}