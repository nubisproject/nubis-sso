# Discover Consul settings
module "consul" {
  source       = "github.com/nubisproject/nubis-terraform//consul?ref=v1.4.0"
  region       = "${var.region}"
  environment  = "${var.environment}"
  account      = "${var.account}"
  service_name = "${var.service_name}"
}

# Configure our Consul provider, module can't do it for us
provider "consul" {
  address    = "${module.consul.address}"
  scheme     = "${module.consul.scheme}"
  datacenter = "${module.consul.datacenter}"
}

# We are a bit special, can't use ${module.consul.config_prefix}
# Publish our outputs into Consul for our application to consume
#resource "consul_keys" "config" {
#  key {
#    path   = "${var.service_name}/${var.environment}/prometheus/config/BackupBucket"
#    value  = "${module.backups.name}"
#    delete = true
#  }
#}
