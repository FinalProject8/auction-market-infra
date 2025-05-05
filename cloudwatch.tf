# --- ADDED: log_router 용 CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "log_router_lg" {
  name              = "/ecs/${var.project_name}/log-router"
  retention_in_days = 7 # 로그 보존 기간
  tags = {
    Name        = "${var.project_name}-log-router-lg"
    Project     = var.project_name
  }
}