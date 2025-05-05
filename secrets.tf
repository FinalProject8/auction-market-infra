resource "aws_secretsmanager_secret" "gcp_key" {
  name        = "${var.project_name}/gcp/service-account-key"
  description = "Stores the GCP Service Account Key JSON for Spring Batch App"

  tags = {
    Name    = "${var.project_name}-gcp-key-secret"
    Project = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "gcp_key" {
  secret_id     = aws_secretsmanager_secret.gcp_key.id
  # sensitive 변수로부터 실제 JSON 내용 주입
  secret_string = file(var.gcp_key_file_path)
}