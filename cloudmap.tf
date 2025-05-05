# 1. Private DNS 네임스페이스 생성
# VPC 내부에서만 사용 가능한 DNS 네임스페이스
# 예: websocket-app.my-spring-infra.local 과 같은 주소 사용 가능
resource "aws_service_discovery_private_dns_namespace" "internal" {
  # 네임스페이스 이름 (원하는 이름으로 변경 가능, 보통 .local, .internal 등 사용)
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for internal service discovery"
  vpc         = aws_vpc.main.id # vpc.tf 에서 정의된 VPC ID 참조

  tags = {
    Name    = "${var.project_name}-namespace"
    Project = var.project_name
  }
}

# 2. WebSocketApp을 위한 서비스 디스커버리 서비스 생성
# ECS Task가 이 서비스 이름으로 Cloud Map에 등록
resource "aws_service_discovery_service" "websocket" {
  # 다른 서비스(AuctionMarketApp)가 이 이름으로 WebSocketApp을 찾음
  name = "websocket-app"

  description = "Service Discovery registration for WebSocket App"

  # 위에서 생성한 Private DNS 네임스페이스와 연결
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    # A 레코드: Task의 IP 주소를 직접 반환하는 방식 (Fargate에 적합)
    dns_records {
      ttl  = 10 # DNS 캐시 TTL (초) - Fargate IP는 변동될 수 있으므로 짧게 설정
      type = "A"
    }

    # MULTIVALUE 라우팅: 여러 개의 healthy Task IP 주소를 반환하도록 허용
    routing_policy = "MULTIVALUE"
  }

  # ECS 자체 상태 확인을 사용하므로 여기서는 별도 상태 확인 비활성화 (선택 사항)
  # health_check_custom_config {
  #   failure_threshold = 1
  # }
}