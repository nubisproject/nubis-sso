variable "account" {
}

variable "region" {
  default = "us-west-2"
}

variable "environment" {
  default = "stage"
}

variable "service_name" {
  default = "sso"
}

variable "instance_type" {
  default = "t2.medium"
}

variable "ami" {}

variable "client_id" {
  default=""
}

variable "client_secret" {
  default=""
}
