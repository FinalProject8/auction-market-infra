# s3.tf (또는 main.tf 등) 파일에 추가

variable "s3_bucket_name" {
  description = "S3 bucket name for product images"
  type        = string
  default     = "auction-market-product-image-bucket"
}

resource "aws_s3_bucket" "product_images" {
  # 버킷 이름은 전역적으로 고유해야 하므로, 계정 ID 등을 포함하는 것이 좋습니다.
  bucket = "${var.s3_bucket_name_prefix}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name    = var.s3_bucket_name
    Project = var.project_name
  }
}