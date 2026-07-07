terraform {
  backend "s3" {
    bucket = "ashwin-cloud-project-tfstate"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "cloudcart-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_s3_bucket" "product_images" {
  bucket = "ashwin-cloudcart-images"
}

resource "aws_s3_bucket_versioning" "product_images_versioning" {
  bucket = aws_s3_bucket.product_images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "product_images_public" {
  bucket     = aws_s3_bucket.product_images.id
  depends_on = [aws_s3_bucket_public_access_block.product_images]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.product_images.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.orders.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cloudcart-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_dynamodb_table" "orders" {
  name             = "cloudcart-orders"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "order_id"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Name = "cloudcart-orders"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "cloudcart-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb_stream" {
  name = "lambda-dynamodb-stream-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:DescribeStream",
        "dynamodb:ListStreams"
      ]
      Resource = aws_dynamodb_table.orders.stream_arn
    }]
  })
}

resource "aws_lambda_function" "order_confirmation" {
  function_name = "cloudcart-order-confirmation"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
}

resource "aws_lambda_event_source_mapping" "orders_stream_trigger" {
  event_source_arn  = aws_dynamodb_table.orders.stream_arn
  function_name     = aws_lambda_function.order_confirmation.arn
  starting_position = "LATEST"
}


resource "aws_launch_template" "app" {
  name_prefix   = "flask-app-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y python3-pip git
    cd /home/ec2-user
    git clone ${var.github_repo_url} app
    cd app/webapp
    pip3 install -r requirements.txt
    python3 app.py &
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "flask-app-instance"
    }
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "flask-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb" "app_alb" {
  name               = "flask-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_autoscaling_group" "app_asg" {
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "flask-app-asg"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "request_count_scaling" {
  name                   = "request-count-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app_alb.arn_suffix}/${aws_lb_target_group.app_tg.arn_suffix}"
    }
    target_value = 30.0
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "cloudcart-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app_alb.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          region = "eu-central-1"
          title  = "ALB Request Count"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app_asg.name]
          ]
          period = 60
          stat   = "Average"
          region = "eu-central-1"
          title  = "Average CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app_alb.arn_suffix]
          ]
          period = 60
          stat   = "Average"
          region = "eu-central-1"
          title  = "Average Response Time"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.app_asg.name]
          ]
          period = 60
          stat   = "Average"
          region = "eu-central-1"
          title  = "In-Service Instance Count"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "cloudcart-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1.0
  alarm_description   = "Alarm when average response time exceeds 1 second"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }
}

resource "aws_sns_topic" "scaling_alerts" {
  name = "cloudcart-scaling-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.scaling_alerts.arn
  protocol  = "email"
  endpoint  = "eshwingg@gmail.com"
}

resource "aws_autoscaling_notification" "asg_notifications" {
  group_names = [aws_autoscaling_group.app_asg.name]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.scaling_alerts.arn
}

resource "aws_budgets_budget" "monthly_threshold" {
  name         = "cloudcart-monthly-threshold"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["eshwingg@gmail.com"]
  }
}

output "alb_url" {
  value = "http://${aws_lb.app_alb.dns_name}"
}
