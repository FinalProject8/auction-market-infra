# terraform/backend.tf

terraform {
  backend "s3" {
    bucket         = "<yujun-bucket>" # 미리 생성한 S3 버킷 이름
    key            = "prod/terraform.tfstate"    # S3 내 상태 파일 경로 (환경별 분리 가능)
    region         = "ap-northeast-2"
    dynamodb_table = "<yujun-table>" # 미리 생성한 DynamoDB 테이블 이름
    encrypt        = true
  }
}