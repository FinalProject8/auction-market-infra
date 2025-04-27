# --- 입력 변수 정의 ---

variable "aws_region" {
  description = "배포할 AWS 리전"
  type        = string
  default     = "ap-northeast-2" # 예: 서울 리전
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 태깅 및 이름 생성에 사용)"
  type        = string
  default     = "my-spring-infra"
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR 목록 (최소 2개 AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private 서브넷 CIDR 목록 (최소 2개 AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "db_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "adminuser" # 예시 값
}

variable "db_name" {
  description = "생성할 데이터베이스 이름"
  type        = string
  default     = "mydatabase" # 예시 값
}

variable "opensearch_domain_name" {
  description = "OpenSearch 도메인 이름 (소문자, 숫자, 하이픈만 가능)"
  type        = string
  default     = "my-opensearch-logs"
}

variable "app1_image_uri" {
  description = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/auction-market-app:latest"
  type        = string
  # 예: 142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/auction-market-app:latest
  # 이 값은 이미지가 ECR에 푸시된 후 정확히 입력해야 합니다.
}

variable "app2_image_uri" {
  description = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/auction-market-realtime"
  type        = string
  # 예: 142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/auction-market-realtime:latest
}