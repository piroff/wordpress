variable "region" {
  type        = string
  description = "Region to use"
}

variable "name" {
  type        = string
  description = "Name of the environment"
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR block"
}

variable "wp_instances" {
  type        = string
  description = "Number of EC2 instane"
}

variable "ami_id" {
  type        = string
  description = "EC2 instances Amazon Image ID"
}

variable "instance_type" {
  type        = string
  description = "EC2 instances image type"
}

variable "ec2_ebs_size"{
  type        = number
  description = "EC2 instances root disk size in GB"
}

variable "rds_instance_class" {
  type        = string
  description = "RDS instance type"
}

variable "db_name" {
  type        = string
  description = "DB name"
}

variable "db_user" {
  type        = string
  description = "DB user"
}
