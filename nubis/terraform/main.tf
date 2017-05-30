provider "aws" {
  profile = "${var.aws_profile}"
  region  = "${var.aws_region}"
}

module "sso-image" {
  source = "github.com/nubisproject/nubis-deploy///modules/images?ref=master"

  region = "${var.aws_region}"
  version = "${var.nubis_version}"
  project = "nubis-sso"
}

resource "aws_security_group" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  name_prefix = "${var.project}-${element(split(",",var.environments), count.index)}-"
  description = "SSO rules"

  vpc_id = "${element(split(",",var.vpc_ids), count.index)}"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    security_groups = [
      "${element(split(",",var.ssh_security_groups), count.index)}",
    ]
  }

  # Traefik
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Traefik 
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Put back Amazon Default egress all rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${element(split(",",var.environments), count.index)}"
    Region      = "${var.aws_region}"
    Environment = "${element(split(",",var.environments), count.index)}"
  }
}

resource "aws_iam_instance_profile" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-${element(split(",",var.environments), count.index)}-${var.aws_region}"

  roles = [
    "${element(aws_iam_role.sso.*.name, count.index)}",
  ]
}

resource "aws_iam_role" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-${element(split(",",var.environments), count.index)}-${var.aws_region}"
  path = "/nubis/${var.project}/"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-route53-${element(split(",",var.environments), count.index)}-${var.aws_region}"
  role = "${element(aws_iam_role.sso.*.id, count.index)}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
        {
            "Action": [
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/${var.zone_id}",
            "Effect": "Allow"
        },
        {
            "Action": [
                "route53:GetChange"
            ],
            "Resource": "arn:aws:route53:::change/*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "route53:ListHostedZonesByName"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeTags"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
POLICY
}

resource "aws_launch_configuration" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  name_prefix = "${var.project}-${element(split(",",var.environments), count.index)}-${var.aws_region}-"
  
  image_id = "${module.sso-image.image_id}"

  instance_type        = "t2.small"
  key_name             = "${var.key_name}"
  iam_instance_profile = "${element(aws_iam_instance_profile.sso.*.name, count.index)}"

  enable_monitoring    = false
  
  associate_public_ip_address = true

  root_block_device = {
    volume_type = "gp2"
    delete_on_termination = true
  }

  security_groups = [
    "${element(aws_security_group.sso.*.id, count.index)}",
    "${element(split(",",var.sso_security_groups), count.index)}",
    "${element(split(",",var.internet_access_security_groups), count.index)}",
    "${element(split(",",var.shared_services_security_groups), count.index)}",
    "${element(split(",",var.ssh_security_groups), count.index)}",
  ]

  user_data = <<EOF
NUBIS_PROJECT="${var.project}"
NUBIS_ENVIRONMENT="${element(split(",",var.environments), count.index)}"
NUBIS_ACCOUNT="${var.service_name}"
NUBIS_TECHNICAL_CONTACT="${var.technical_contact}"
NUBIS_DOMAIN="${var.nubis_domain}"
NUBIS_SUDO_GROUPS="${var.nubis_sudo_groups}"
NUBIS_USER_GROUPS="${var.nubis_user_groups}"
NUBIS_SSO_ZONEID="${var.zone_id}"
NUBIS_SSO_OPENID_DOMAIN="${var.openid_domain}"
EOF
}

resource "aws_autoscaling_group" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  #XXX: Fugly, assumes 3 subnets per environments, bad assumption, but valid ATM
  vpc_zone_identifier = [
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 0 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 1 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 2 )}",
  ]

  name                      = "${var.project}-${element(split(",",var.environments), count.index)} (LC ${element(aws_launch_configuration.sso.*.name, count.index)})"
  max_size                  = "2"
  min_size                  = "1"
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = "1"
  force_delete              = true
  launch_configuration      = "${element(aws_launch_configuration.sso.*.name, count.index)}"

  wait_for_capacity_timeout = "60m"

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "SSO (${var.nubis_version}) for ${var.service_name} in ${element(split(",",var.environments), count.index)}"
    propagate_at_launch = true
  }

  tag {
    key                 = "ServiceName"
    value               = "${var.project}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "${element(split(",",var.environments), count.index)}"
    propagate_at_launch = true
  }
}

# This null resource is responsible for storing our secrets into KMS
resource "null_resource" "secrets" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  # Important to list here every variable that affects what needs to be put into KMS
  triggers {
    credstash_key = "${var.credstash_key}"
    client_id     = "${var.openid_client_id}"
    client_secret = "${var.openid_client_secret}"
    region        = "${var.aws_region}"
    version       = "${var.nubis_version}"
    context       = "-E region:${var.aws_region} -E environment:${element(split(",",var.environments), count.index)} -E service:${var.project}"
    unicreds      = "unicreds -r ${var.aws_region} put -k ${var.credstash_key} ${var.project}/${element(split(",",var.environments), count.index)}"
    unicreds_file = "unicreds -r ${var.aws_region} put-file -k ${var.credstash_key} ${var.project}/${element(split(",",var.environments), count.index)}"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/openid/client_id ${var.openid_client_id} ${self.triggers.context}"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/openid/client_secret ${var.openid_client_secret} ${self.triggers.context}"
  }
}

resource "aws_elasticache_subnet_group" "sso" {
  count       = "${var.persistent_sessions * var.enabled * length(split(",", var.environments))}"
  name        = "${var.project}-${element(split(",",var.environments), count.index)}-sessions-subnetgroup"
  description = "Subnet Group for SSO Sessions in ${element(split(",",var.environments), count.index)}"

  #XXX: Fugly, assumes 3 subnets per environments, bad assumption, but valid ATM
  subnet_ids = [
    "${element(split(",",var.subnet_ids), (count.index * 3) + 0 )}",
    "${element(split(",",var.subnet_ids), (count.index * 3) + 1 )}",
    "${element(split(",",var.subnet_ids), (count.index * 3) + 2 )}",
  ]
}

resource "aws_security_group" "cache" {
  count  = "${var.persistent_sessions * var.enabled * length(split(",", var.environments))}"
  vpc_id = "${element(split(",",var.vpc_ids), count.index)}"

  ingress {
    from_port = 11211
    to_port   = 11211
    protocol  = "tcp"

    security_groups = [
      "${element(aws_security_group.sso.*.id, count.index)}",
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name           = "${var.project}-${element(split(",",var.environments), count.index)}-sessions"
    Region         = "${var.aws_region}"
    Environment    = "${element(split(",",var.environments), count.index)}"
    TechnicalOwner = "${var.technical_contact}"
  }
}
