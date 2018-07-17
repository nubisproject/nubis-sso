variable aws_region {}

variable key_name {}

variable nubis_version {}

variable nubis_domain {}

variable zone_id {}

variable service_name {}

variable arenas {
  type = "list"
}

variable enabled {}

variable technical_contact {}

variable vpc_ids {}

variable subnet_ids {}

variable public_subnet_ids {}

variable ssh_security_groups {}

variable monitoring_security_groups {}

variable internet_access_security_groups {}

variable shared_services_security_groups {}

variable sso_security_groups {}

variable project {
  default = "sso"
}

variable nubis_sudo_groups {
  default = "nubis_sudo_groups"
}

variable nubis_oper_groups {
  default = ""
}

variable nubis_user_groups {
  default = ""
}

variable "credstash_key" {
  description = "KMS Key ID used for Credstash (aaaabbbb-cccc-dddd-1111-222233334444)"
}

variable "credstash_dynamodb_table" {}

variable "openid_client_id" {
  default = "OPENID_CLIENT_ID_DEFAULT"
}

variable "openid_client_secret" {
  default = "OPENID_CLIENT_SECRET_DEFAULT"
}

variable "openid_domain" {
  default = "mozilla"
}

variable "persistent_sessions" {
  default = true
}
