provider "aws" {
  region = "${var.aws_region}"
}

module "sso-image" {
  source = "github.com/nubisproject/nubis-terraform//images?ref=v2.4.0"

  region        = "${var.aws_region}"
  image_version = "${var.nubis_version}"
  project       = "nubis-sso"
}

resource "aws_security_group" "sso" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name_prefix = "${var.project}-${element(var.arenas, count.index)}-"
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
    Name   = "${var.project}-${element(var.arenas, count.index)}"
    Region = "${var.aws_region}"
    Arena  = "${element(var.arenas, count.index)}"
  }
}

resource "aws_iam_instance_profile" "sso" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-${element(var.arenas, count.index)}-${var.aws_region}"

  role = "${element(aws_iam_role.sso.*.name, count.index)}"
}

resource "aws_iam_role" "sso" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-${element(var.arenas, count.index)}-${var.aws_region}"
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
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name = "${var.project}-route53-${element(var.arenas, count.index)}-${var.aws_region}"
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

resource "aws_iam_role_policy" "scout" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name   = "${var.project}-scout-${element(var.arenas, count.index)}-${var.aws_region}"
  role   = "${element(aws_iam_role.sso.*.id, count.index)}"
  policy = "${file("${path.module}/Scout2-Default.json")}"
}

resource "aws_launch_configuration" "sso" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name_prefix = "${var.project}-${element(var.arenas, count.index)}-${var.aws_region}-"

  image_id = "${module.sso-image.image_id}"

  instance_type        = "t2.small"
  key_name             = "${var.key_name}"
  iam_instance_profile = "${element(aws_iam_instance_profile.sso.*.name, count.index)}"

  enable_monitoring = false

  associate_public_ip_address = true

  root_block_device = {
    volume_type           = "gp2"
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
NUBIS_ARENA="${element(var.arenas, count.index)}"
NUBIS_ACCOUNT="${var.service_name}"
NUBIS_SSO_READONLY_ROLE="${aws_iam_role.readonly.arn}"
NUBIS_TECHNICAL_CONTACT="${var.technical_contact}"
NUBIS_DOMAIN="${var.nubis_domain}"
NUBIS_SUDO_GROUPS="${var.nubis_sudo_groups}"
NUBIS_OPER_GROUPS="${var.nubis_oper_groups}"
NUBIS_USER_GROUPS="${var.nubis_user_groups}"
NUBIS_SSO_ZONEID="${var.zone_id}"
NUBIS_SSO_OPENID_DOMAIN="${var.openid_domain}"
NUBIS_SSO_MEMCACHED="${element(aws_elasticache_cluster.cache.*.configuration_endpoint, count.index)}"
EOF
}

resource "aws_autoscaling_group" "sso" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  #XXX: Fugly, assumes 3 subnets per arenas, bad assumption, but valid ATM
  vpc_zone_identifier = [
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 0 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 1 )}",
    "${element(split(",",var.public_subnet_ids), (count.index * 3) + 2 )}",
  ]

  name                      = "${var.project}-${element(var.arenas, count.index)} (LC ${element(aws_launch_configuration.sso.*.name, count.index)})"
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
    value               = "SSO (${var.nubis_version}) for ${var.service_name} in ${element(var.arenas, count.index)}"
    propagate_at_launch = true
  }

  tag {
    key                 = "ServiceName"
    value               = "${var.project}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Arena"
    value               = "${element(var.arenas, count.index)}"
    propagate_at_launch = true
  }
}

# This null resource is responsible for storing our secrets into KMS
resource "null_resource" "secrets" {
  count = "${var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  # Important to list here every variable that affects what needs to be put into KMS
  triggers {
    credstash_key   = "${var.credstash_key}"
    client_id       = "${var.openid_client_id}"
    client_secret   = "${var.openid_client_secret}"
    iam_user_id     = "${aws_iam_access_key.sso.id}"
    iam_user_secret = "${aws_iam_access_key.sso.secret}"
    region          = "${var.aws_region}"
    version         = "${var.nubis_version}"
    context         = "-E region:${var.aws_region} -E arena:${element(var.arenas, count.index)} -E service:${var.project}"
    unicreds        = "unicreds -r ${var.aws_region} put -k ${var.credstash_key} ${var.project}/${element(var.arenas, count.index)}"
    unicreds_rm     = "unicreds -r ${var.aws_region} delete -k ${var.credstash_key} ${var.project}/${element(var.arenas, count.index)}"
    unicreds_file   = "unicreds -r ${var.aws_region} put-file -k ${var.credstash_key} ${var.project}/${element(var.arenas, count.index)}"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/openid/client_id ${var.openid_client_id} ${self.triggers.context}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "${self.triggers.unicreds_rm}/openid/client_id"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/openid/client_secret ${var.openid_client_secret} ${self.triggers.context}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "${self.triggers.unicreds_rm}/openid/client_secret"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/iam/client_id ${aws_iam_access_key.sso.id} ${self.triggers.context}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "${self.triggers.unicreds_rm}/iam/client_id"
  }

  provisioner "local-exec" {
    command = "${self.triggers.unicreds}/iam/client_secret ${aws_iam_access_key.sso.secret} ${self.triggers.context}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "${self.triggers.unicreds_rm}/iam/client_secret"
  }
}

resource "aws_elasticache_subnet_group" "sso" {
  count = "${var.persistent_sessions * var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  name        = "${var.project}-${element(var.arenas, count.index)}-sessions-subnetgroup"
  description = "Subnet Group for SSO Sessions in ${element(var.arenas, count.index)}"

  #XXX: Fugly, assumes 3 subnets per arenas, bad assumption, but valid ATM
  subnet_ids = [
    "${element(split(",",var.subnet_ids), (count.index * 3) + 0 )}",
    "${element(split(",",var.subnet_ids), (count.index * 3) + 1 )}",
    "${element(split(",",var.subnet_ids), (count.index * 3) + 2 )}",
  ]
}

resource "aws_security_group" "sessions" {
  count = "${var.persistent_sessions * var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

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
    Name           = "${var.project}-${element(var.arenas, count.index)}-sessions"
    Region         = "${var.aws_region}"
    Arena          = "${element(var.arenas, count.index)}"
    TechnicalOwner = "${var.technical_contact}"
  }
}

resource "aws_elasticache_cluster" "cache" {
  count = "${var.persistent_sessions * var.enabled * length(var.arenas)}"

  lifecycle {
    create_before_destroy = true
  }

  cluster_id        = "${var.project}-${element(var.arenas, count.index)}-sessions"
  engine            = "memcached"
  node_type         = "cache.t2.micro"
  port              = 11211
  num_cache_nodes   = 1
  apply_immediately = true
  subnet_group_name = "${element(aws_elasticache_subnet_group.sso.*.name, count.index)}"

  security_group_ids = [
    "${element(aws_security_group.sessions.*.id, count.index)}",
  ]

  tags = {
    Name           = "${var.project}-${element(var.arenas, count.index)}-sessions"
    Region         = "${var.aws_region}"
    Arena          = "${element(var.arenas, count.index)}"
    TechnicalOwner = "${var.technical_contact}"
  }
}

resource "aws_iam_user" "sso" {
  count = "${var.enabled}"
  path  = "/nubis/sso/"
  name  = "readonly-${var.aws_region}"

  force_destroy = true
}

resource "aws_iam_access_key" "sso" {
  count = "${var.enabled}"
  user  = "${aws_iam_user.sso.name}"
}

resource "aws_iam_role" "readonly" {
  count = "${var.enabled}"
  path  = "/nubis/sso/"
  name  = "readonly-${var.aws_region}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal" : { "AWS" : "${aws_iam_user.sso.arn}" },
      "Effect": "Allow",
      "Sid": "readonly"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "readonly" {
  count       = "${var.enabled}"
  name        = "readonly-${var.aws_region}"
  path        = "/nubis/sso/"
  description = "SSO Dashboard Policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:Describe*",
                "cloudformation:Describe*",
                "cloudformation:Get*",
                "cloudformation:List*",
                "cloudformation:Estimate*",
                "cloudformation:Preview*",
                "cloudfront:Get*",
                "cloudfront:List*",
                "cloudtrail:Describe*",
                "cloudtrail:Get*",
                "cloudtrail:List*",
                "cloudtrail:LookupEvents",
                "cloudwatch:Describe*",
                "cloudwatch:Get*",
                "cloudwatch:List*",
                "config:Deliver*",
                "config:Describe*",
                "config:Get*",
                "config:List*",
                "dynamodb:BatchGet*",
                "dynamodb:Describe*",
                "dynamodb:Get*",
                "dynamodb:List*",
                "dynamodb:Query",
                "dynamodb:Scan",
                "ec2:Describe*",
                "ec2:Get*",
                "ec2messages:Get*",
                "elasticache:Describe*",
                "elasticache:List*",
                "elasticfilesystem:Describe*",
                "elasticloadbalancing:Describe*",
                "es:Describe*",
                "es:List*",
                "es:ESHttpGet",
                "es:ESHttpHead",
                "events:Describe*",
                "events:List*",
                "events:Test*",
                "health:Describe*",
                "health:Get*",
                "health:List*",
                "iam:Generate*",
                "iam:Get*",
                "iam:List*",
                "iam:Simulate*",
                "inspector:Describe*",
                "inspector:Get*",
                "inspector:List*",
                "inspector:Preview*",
                "inspector:LocalizeText",
                "kms:Describe*",
                "kms:Get*",
                "kms:List*",
                "lambda:List*",
                "lambda:Get*",
                "logs:Describe*",
                "logs:Get*",
                "logs:FilterLogEvents",
                "logs:ListTagsLogGroup",
                "logs:TestMetricFilter",
                "organizations:Describe*",
                "organizations:List*",
                "rds:Describe*",
                "rds:List*",
                "rds:Download*",
                "route53:Get*",
                "route53:List*",
                "route53:Test*",
                "route53domains:Check*",
                "route53domains:Get*",
                "route53domains:List*",
                "route53domains:View*",
                "s3:Get*",
                "s3:List*",
                "s3:Head*",
                "ses:Get*",
                "ses:List*",
                "ses:Describe*",
                "ses:Verify*",
                "sns:Get*",
                "sns:List*",
                "sns:Check*",
                "sqs:Get*",
                "sqs:List*",
                "sqs:Receive*",
                "states:List*",
                "states:Describe*",
                "states:GetExecutionHistory",
                "sts:Get*",
                "swf:Count*",
                "swf:Describe*",
                "swf:Get*",
                "swf:List*",
                "tag:Get*",
                "trustedadvisor:Describe*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "read_only" {
  count      = "${var.enabled}"
  name       = "read-only-attachments-${var.aws_region}"
  users      = ["${aws_iam_user.sso.name}"]
  roles      = ["${aws_iam_role.readonly.name}"]
  policy_arn = "${aws_iam_policy.readonly.arn}"
}
