# terraform.tfvars 파일 내용
auction_image_uri        = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/my-auction-app:74db168"
websocket_app_image_uri = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/websocket-app:b5043d6"
batch_app_image_uri     = "142043808465.dkr.ecr.ap-northeast-2.amazonaws.com/spring-batch-app:8cb127a"
logstash_host = "10.0.1.162"
logstash_port = "5044"
# ... 기타 필요한 변수 값들 ...
# 필요하다면 다른 변수들도 여기에 추가할 수 있습니다. 예를 들어:
# project_name = "my-prod-infra"
# db_username = "prodadmin"