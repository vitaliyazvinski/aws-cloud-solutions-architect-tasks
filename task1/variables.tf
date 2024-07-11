variable "aws_profile" {
  description = "The AWS CLI profile to use"
  type        = string
}

variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to create resources in"
  type        = string
}

variable "subscription_email" {
  description = "The email address to subscribe to the SNS topic"
  type        = string
}