variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for the bucket and distribution"
  type        = string
  default     = "ammaar-homelab-site"
}
