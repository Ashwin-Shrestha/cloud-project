variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type for the app servers"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "ami_id" {
  description = "AMI ID for the EC2 launch template (Amazon Linux 2023)"
  type        = string
  default     = "ami-0669b163befffbdfc"
}

variable "github_repo_url" {
  description = "GitHub repository URL the app code is pulled from"
  type        = string
  default     = "https://github.com/Ashwin-Shrestha/cloud-project.git"
}
