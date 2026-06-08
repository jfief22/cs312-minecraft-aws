variable "aws_region" {
  description = "AWS region to deploy into. Learner Lab is typically us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Tag/name prefix applied to all resources."
  type        = string
  default     = "minecraft"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small minimum, t3.medium recommended for vanilla Minecraft."
  type        = string
  default     = "t3.medium"
}

variable "minecraft_port" {
  description = "TCP port the Minecraft server listens on."
  type        = number
  default     = 25565
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH for Ansible configuration. Open by default; restrict to your IP for tighter security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "minecraft_allowed_cidr" {
  description = "CIDR block allowed to reach the Minecraft port. Open by default so anyone can join."
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Name of the SSH key pair to create in AWS."
  type        = string
  default     = "minecraft-key"
}
