# lambda.tf 또는 main.tf 등에 추가

# 1. Lambda 실행 역할 생성
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"

  # Lambda 서비스가 이 역할을 Assume(수임)할 수 있도록 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-lambda-exec-role" }
}

# 2. Lambda 실행 역할에 필요한 권한 정책 정의
resource "aws_iam_policy" "lambda_exec_policy" {
  name        = "${var.project_name}-lambda-exec-policy"
  description = "Policy for Lambda function execution"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 기본 Lambda 실행 권한 (CloudWatch Logs)
      {
        Sid    = "AllowLogging",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*" # 모든 로그 리소스에 허용 (필요시 제한)
      },
      # VPC 내 실행 및 RDS 접근을 위한 네트워크 인터페이스(ENI) 생성/관리 권한
      {
        Sid    = "AllowVPCAccess",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses", # 필요시
          "ec2:UnassignPrivateIpAddresses" # 필요시
        ],
        Effect   = "Allow",
        Resource = "*" # VPC 관련 리소스 전체에 허용
      },
      # RDS 접근을 위해 DB 비밀번호 읽기 권한 (Secrets Manager 사용 가정)
      {
        Sid    = "AllowReadDBPasswordSecretForLambda",
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # 필요한 경우
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.db_password.arn # rds.tf 참조
      }
      # 만약 Lambda가 RDS에 IAM 인증을 사용한다면 rds-db:connect 권한 추가
      # 만약 Lambda가 다른 AWS 서비스(S3 등)를 호출한다면 해당 권한 추가
    ]
  })
}

# 3. 생성한 정책을 Lambda 실행 역할에 연결
resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

# (대안) AWS 관리형 정책을 사용할 수도 있습니다.
# resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
#   role       = aws_iam_role.lambda_exec_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }
# resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
#   role       = aws_iam_role.lambda_exec_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
# }
# + Secrets Manager 접근 등 필요한 커스텀 정책은 별도로 연결