# --- RDS (MySQL) 및 Secrets Manager ---

# DB Subnet Group (Private 서브넷 사용)
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

# 랜덤 비밀번호 생성 (Secrets Manager 저장용)
resource "random_password" "db_password" {
  length           = 16
  special          = false # <--- 특수 문자 사용 안 함으로 변경 (가장 간단)
  upper            = true  # 대문자, 소문자, 숫자는 포함
  lower            = true
  numeric = true
}

# AWS Secrets Manager에 비밀번호 저장
resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.project_name}/rds/masterpassword"
  tags = { Name = "${var.project_name}-rds-password-secret" }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

# RDS MySQL 인스턴스 생성
resource "aws_db_instance" "main" {
  identifier           = "${var.project_name}-rds-mysql"
  allocated_storage    = 20 # GB
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro" # 비용 고려
  db_name              = var.db_name
  username             = var.db_username
  password             = random_password.db_password.result # 비밀번호
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id] # RDS 보안 그룹 연결
  skip_final_snapshot  = true # 테스트용
  publicly_accessible  = false # Private 배치

  tags = {
    Name = "${var.project_name}-rds-mysql"
  }
}