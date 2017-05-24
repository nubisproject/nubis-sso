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

    security_groups = [
      "${element(split(",",var.ssh_security_groups), count.index)}",
      "${element(aws_security_group.sso-elb.*.id, count.index)}",
    ]
  }

  # Traefik 
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    security_groups = [
      "${element(split(",",var.ssh_security_groups), count.index)}",
      "${element(aws_security_group.sso-elb.*.id, count.index)}",
    ]
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

  root_block_device = {
#    volume_size = "8"
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
EOF
}

#resource "aws_autoscaling_group" "sso" {
#  count = "${var.enabled * length(split(",", var.environments))}"
#
#  #XXX: Fugly, assumes 3 subnets per environments, bad assumption, but valid ATM
#  vpc_zone_identifier = [
#    "${element(split(",",var.subnet_ids), (count.index * 3) + 0 )}",
#    "${element(split(",",var.subnet_ids), (count.index * 3) + 1 )}",
#    "${element(split(",",var.subnet_ids), (count.index * 3) + 2 )}",
#  ]
#
#  name                      = "${var.project}-${element(split(",",var.environments), count.index)} (LC ${element(aws_launch_configuration.prometheus.*.name, count.index)})"
#  max_size                  = "2"
#  min_size                  = "1"
#  health_check_grace_period = 300
#  health_check_type         = "ELB"
#  desired_capacity          = "1"
#  force_delete              = true
#  launch_configuration      = "${element(aws_launch_configuration.prometheus.*.name, count.index)}"
#
#  wait_for_capacity_timeout = "60m"
#
#  load_balancers = [
#    "${element(aws_elb.traefik.*.name, count.index)}",
#  ]
#
#  enabled_metrics = [
#    "GroupMinSize",
#    "GroupMaxSize",
#    "GroupDesiredCapacity",
#    "GroupInServiceInstances",
#    "GroupPendingInstances",
#    "GroupStandbyInstances",
#    "GroupTerminatingInstances",
#    "GroupTotalInstances",
#  ]
#
#  tag {
#    key                 = "Name"
#    value               = "Prometheus (${var.nubis_version}) for ${var.service_name} in ${element(split(",",var.environments), count.index)}"
#    propagate_at_launch = true
#  }
#
#  tag {
#    key                 = "ServiceName"
#    value               = "${var.project}"
#    propagate_at_launch = true
#  }
#
#  tag {
#    key                 = "Environment"
#    value               = "${element(split(",",var.environments), count.index)}"
#    propagate_at_launch = true
#  }
#}
#

resource "aws_security_group" "sso-elb" {
  count = "${var.enabled * length(split(",", var.environments))}"

  lifecycle {
    create_before_destroy = true
  }

  name        = "sso-elb-${element(split(",",var.environments), count.index)}"
  description = "Allow inbound traffic for SSO"

  vpc_id      = "${element(split(",",var.vpc_ids), count.index)}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Put back Amazon Default egress all rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "sso" {
  count = "${var.enabled * length(split(",", var.environments))}"

  #XXX
  lifecycle {
    create_before_destroy = true
  }

  name = "sso-${element(split(",",var.environments), count.index)}"

  #XXX: Fugly, assumes 3 subnets per environments, bad assumption, but valid ATM
  subnets = [
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 0 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 1 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 2 )}",
  ]

  # This is an internet facing ELB
  internal = false

  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    target              = "TCP:80"
    interval            = 30
  }

  cross_zone_load_balancing = true

  security_groups = [
    "${element(aws_security_group.sso-elb.*.id, count.index)}",
  ]

  tags = {
    Name        = "sso-${element(split(",",var.environments), count.index)}"
    Region      = "${var.aws_region}"
    Environment = "${element(split(",",var.environments), count.index)}"
  }
}

resource "aws_route53_record" "sso" {
  count   = "${var.enabled * length(split(",", var.environments))}"
  zone_id = "${var.zone_id}"

  name = "n3s.${element(split(",",var.environments), count.index)}"
  type = "A"

  alias {
    name                   = "${element(aws_elb.sso.*.dns_name,count.index)}"
    zone_id                = "${element(aws_elb.sso.*.zone_id,count.index)}"
    evaluate_target_health = true
  }
}
