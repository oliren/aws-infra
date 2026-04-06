provider "twingate" {
  api_token = var.twingate_api_token
  network   = var.twingate_network
}


resource "twingate_remote_network" "aws_network" {
  name = "Playground"
}

resource "twingate_connector" "aws_connector" {
  remote_network_id = twingate_remote_network.aws_network.id
}

resource "twingate_connector_tokens" "aws_connector_tokens" {
  connector_id = twingate_connector.aws_connector.id
}

data "aws_ami" "latest" {
  most_recent = true
  filter {
    name = "name"
    values = [
      "twingate/images/hvm-ssd/twingate-amd64-*",
    ]
  }
  owners = ["617935088040"]
}

module "twingate_sg" {
  source             = "terraform-aws-modules/security-group/aws"
  version            = "~> 5.1"
  vpc_id             = module.vpc.vpc_id
  name               = "twingate_security_group"
  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-tcp", "all-udp", "all-icmp"]
}

module "ec2_tenant_connector" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.4"

  name                   = "twingate_connector"
  user_data              = <<-EOT
    #!/bin/bash
    set -e
    mkdir -p /etc/twingate/
    {
      echo TWINGATE_URL="https://${var.twingate_network}.twingate.com"
      echo TWINGATE_ACCESS_TOKEN="${twingate_connector_tokens.aws_connector_tokens.access_token}"
      echo TWINGATE_REFRESH_TOKEN="${twingate_connector_tokens.aws_connector_tokens.refresh_token}"
    } > /etc/twingate/connector.conf
    sudo systemctl enable --now twingate-connector
  EOT
  ami                    = data.aws_ami.latest.id
  instance_type          = "t3a.micro"
  vpc_security_group_ids = [module.twingate_sg.security_group_id]
  subnet_id              = module.vpc.private_subnets[0]


}

data "twingate_groups" "all" {
  name = "Everyone"
}

resource "twingate_resource" "tg_vpc" {
  name = "Playground VPC"
  address = local.vpc_cidr
  remote_network_id = twingate_remote_network.aws_network.id

  access_group {
    group_id                           = data.twingate_groups.all.groups[0].id
  }

}