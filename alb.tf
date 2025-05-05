# --- ALB (Application Load Balancer) ---

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id] # Public 서브넷 배치

  enable_deletion_protection = false

  tags = { Name = "${var.project_name}-alb" }
}

# Target Group (AuctionMarket 용)
resource "aws_lb_target_group" "app1" {
  name        = "${var.project_name}-app1-tg"
  port        = 8080 # 컨테이너 포트
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate

  health_check {
    enabled             = true
    path                = "/actuator/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
  tags = { Name = "${var.project_name}-app1-tg" }
}

# Target Group (WebSocket 용)
resource "aws_lb_target_group" "app2" {
  name        = "${var.project_name}-app2-tg"
  port        = 8081 # 컨테이너 포트 (App2도 8080 가정)
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate

  health_check {
    enabled             = true
    path                = "/actuator/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
  tags = { Name = "${var.project_name}-app2-tg" }
}

# ALB Listener (HTTP:80) - HTTPS 사용 시 추가 설정 (ACM 인증서 등) 필요
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # 기본 동작: App1으로 트래픽 전달 (규칙 필요 시 아래 정의)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app1.arn
  }
}

# Listener Rule (선택 사항 - 예: /app2 경로를 App2로 라우팅)
resource "aws_lb_listener_rule" "app2_path" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app2.arn
  }

  condition {
    path_pattern {
      values = ["/app2/*"]
    }
  }
}