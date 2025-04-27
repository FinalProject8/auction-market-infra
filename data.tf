# --- 데이터 소스 정의 ---

# 현재 리전에서 사용 가능한 가용 영역 목록 조회
data "aws_availability_zones" "available" {
  state = "available"
}

# 현재 AWS 호출자(계정 ID 등) 정보 조회
data "aws_caller_identity" "current" {}