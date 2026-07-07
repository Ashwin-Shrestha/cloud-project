
terraform {
  backend "s3" {
    bucket = "ashwin-cloud-project-tfstate"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}


provider "aws" {
  region = "eu-central-1"
}

# Use default VPC and subnets (no NAT Gateway needed = stays free tier)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for the load balancer (allows HTTP from internet)
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

# Security group for EC2 instances (allows HTTP only from the ALB)
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

# Launch template: defines what each EC2 instance looks like
resource "aws_launch_template" "app" {
  name_prefix   = "flask-app-"
  image_id      = "ami-0669b163befffbdfc" # Amazon Linux 2023, eu-central-1
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

 user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y python3-pip
    pip3 install flask requests
    cat <<'PYEOF' > /home/ec2-user/app.py
    from flask import Flask
    import requests
    import socket
    import datetime

    app = Flask(__name__)

    @app.route("/")
    def hello():
        try:
            instance_id = requests.get(
                "http://169.254.169.254/latest/meta-data/instance-id",
                timeout=1
            ).text
        except Exception:
            instance_id = "unknown"

        hostname = socket.gethostname()
        now = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

        html = f"""
        <html>
        <head>
            <title>Cloud Deployment Demo</title>
            <style>
                body {{
                    font-family: -apple-system, Segoe UI, Roboto, sans-serif;
                    background: linear-gradient(135deg, #1e293b, #0f172a);
                    color: #f1f5f9;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    margin: 0;
                }}
                .card {{
                    background: #1e293b;
                    border: 1px solid #334155;
                    border-radius: 16px;
                    padding: 40px 50px;
                    box-shadow: 0 10px 40px rgba(0,0,0,0.4);
                    text-align: center;
                }}
                h1 {{ font-size: 22px; margin-bottom: 4px; color: #38bdf8; }}
                .status {{
                    display: inline-block;
                    background: #16a34a;
                    color: white;
                    padding: 4px 14px;
                    border-radius: 999px;
                    font-size: 13px;
                    margin-bottom: 20px;
                }}
                .row {{ margin: 10px 0; font-size: 14px; color: #cbd5e1; }}
                .label {{ color: #64748b; }}
                .value {{ color: #f8fafc; font-weight: 600; }}
            </style>
        </head>
        <body>
            <div class="card">
                <h1>AWS Auto-Scaled Deployment</h1>
                <div class="status">HEALTHY</div>
                <div class="row"><span class="label">Instance ID:</span> <span class="value">{instance_id}</span></div>
                <div class="row"><span class="label">Hostname:</span> <span class="value">{hostname}</span></div>
                <div class="row"><span class="label">Server Time:</span> <span class="value">{now}</span></div>
                <div class="row"><span class="label">Deployed via:</span> <span class="value">Terraform + GitHub Actions</span></div>
            </div>
        </body>
        </html>
        """
        return html

    if __name__ == "__main__":
        app.run(host="0.0.0.0", port=80)
    PYEOF
    python3 /home/ec2-user/app.py &
  EOF
  )


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "flask-app-instance"
    }
  }
}

# Target group: where the ALB sends traffic
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

# Application Load Balancer
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

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity    = 2
  min_size            = 1
  max_size            = 4
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

# Auto scaling policy: scale based on CPU utilization
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

# Output the ALB URL so we can access the app
output "alb_url" {
  value = "http://${aws_lb.app_alb.dns_name}"
}