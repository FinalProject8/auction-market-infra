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

variable "auction_image_uri" {
  description = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/my-auction-app"
  type        = string
}

variable "websocket_app_image_uri" {
  description = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/websocket-app"
  type        = string
}

variable "batch_app_image_uri" {
  description = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/spring-batch-app"
  type        = string
}

variable "s3_bucket_name_prefix" {
  description = "S3 버킷 이름 생성 시 사용할 접두사 (이미지 저장용)"
  type        = string
  default     = "auction-market-prod-img" # 고유성 위해 뒤에 계정 ID 등이 붙음
}

variable "logstash_host" {
  description = "Hostname or IP address of the Logstash EC2 instance"
  type        = string
}

variable "logstash_port" {
  description = "Port number for the Logstash Beats input"
  type        = string
  default     = "5044" # 기본값 또는 실제 포트
}

variable "gcp_key_file_path" {
  description = "GCP 서비스 계정 키 JSON 파일 경로 (Terraform 실행 위치 기준)"
  type        = string
  default     = "gcp-key.json" # 루트에 파일 위치 가정
}