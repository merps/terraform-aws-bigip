provider "aws" {
  region = local.region
}

#
# Variables used by this example
#

locals {
  prefix            = "tf-aws-bigip"
  region            = "us-west-1"
  azs               = [format("%s%s", local.region, "a"), format("%s%s", local.region, "b")]
  cidr              = "10.0.0.0/16"
  allowed_mgmt_cidr = "0.0.0.0/0"
  allowed_app_cidr  = "0.0.0.0/0"
  bigip_map = {
    0 = {
      network_interfaces = {
        0 = {
          subnet_id = module.vpc.database_subnets[0]
          subnet_security_group_ids = [
            module.web_server_secure_sg.this_security_group_id,
            module.ssh_secure_sg.this_security_group_id
          ]
          interface_type    = "mgmt"
          public_ip         = true
          private_ips_count = 0
        },
        1 = {
          subnet_id = module.vpc.public_subnets[0]
          subnet_security_group_ids = [
            module.web_server_sg.this_security_group_id,
            module.web_server_secure_sg.this_security_group_id
          ]
          interface_type    = "public"
          public_ip         = true
          private_ips_count = 0
        }
        2 = {
          subnet_id = slice(module.vpc.private_subnets, 0, 1)[0]
          subnet_security_group_ids = [
            module.vpc.default_security_group_id
          ]
          interface_type    = "private"
          public_ip         = false
          private_ips_count = 0
        }
        3 = {
          subnet_id = slice(module.vpc.private_subnets, 2, 3)[0]
          subnet_security_group_ids = [
            module.vpc.default_security_group_id
          ]
          interface_type    = "private"
          public_ip         = false
          private_ips_count = 0
        }
      }
    },
    1 = {
      network_interfaces = {
        0 = {
          subnet_id = module.vpc.database_subnets[1]
          subnet_security_group_ids = [
            module.web_server_secure_sg.this_security_group_id,
            module.ssh_secure_sg.this_security_group_id
          ]
          interface_type    = "mgmt"
          public_ip         = true
          private_ips_count = 0
        },
        1 = {
          subnet_id = module.vpc.public_subnets[1]
          subnet_security_group_ids = [
            module.web_server_sg.this_security_group_id,
            module.web_server_secure_sg.this_security_group_id
          ]
          interface_type    = "public"
          public_ip         = true
          private_ips_count = 0
        }
        2 = {
          subnet_id = slice(module.vpc.private_subnets, 1, 2)[0]
          subnet_security_group_ids = [
            module.vpc.default_security_group_id
          ]
          interface_type    = "private"
          public_ip         = false
          private_ips_count = 0
        }
        3 = {
          subnet_id = slice(module.vpc.private_subnets, 3, 4)[0]
          subnet_security_group_ids = [
            module.vpc.default_security_group_id
          ]
          interface_type    = "private"
          public_ip         = false
          private_ips_count = 0
        }
      }
    }
  }

  test = {
    for bigip, bigip_data in local.bigip_map : bigip => {
      for id, network_interface in bigip_data.network_interfaces : "${bigip}.${id}" => {
        bigip     = bigip
        id        = id
        subnet_id = network_interface.subnet_id
      }
    }
  }
}

#
# Create a random id
#
resource "random_id" "id" {
  byte_length = 2
}

#
# Create random password for BIG-IP
#
resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = " #%*+,-./:=?@[]^_~"
}

#
# Create Secret Store and Store BIG-IP Password
#
resource "aws_secretsmanager_secret" "bigip" {
  name = format("%s-bigip-secret-%s", var.prefix, random_id.id.hex)
}
resource "aws_secretsmanager_secret_version" "bigip-pwd" {
  secret_id     = aws_secretsmanager_secret.bigip.id
  secret_string = random_password.password.result
}

#
# Create the VPC 
#
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = format("%s-vpc-%s", local.prefix, random_id.id.hex)
  cidr                 = local.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  azs = local.azs

  public_subnets = [
    for num in range(length(local.azs)) :
    cidrsubnet(local.cidr, 8, num)
  ]

  # using the database subnet method since it allows a public route
  database_subnets = [
    for num in range(length(local.azs)) :
    cidrsubnet(local.cidr, 8, num + 10)
  ]
  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = true

  private_subnets = [
    # we need to double the number since we have 4 interfaces
    for num in range(length(local.azs) * 2) :
    cidrsubnet(local.cidr, 8, num + 20)
  ]

  tags = {
    Name        = format("%s-vpc-%s", local.prefix, random_id.id.hex)
    Terraform   = "true"
    Environment = "dev"
  }
}

#
# Create a security group for port 80 traffic
#
module "web_server_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = format("%s-web-server-%s", local.prefix, random_id.id.hex)
  description = "Security group for web-server with HTTP ports"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_app_cidr]
}

#
# Create a security group for port 443 traffic
#
module "web_server_secure_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/https-443"

  name        = format("%s-web-server-secure-%s", local.prefix, random_id.id.hex)
  description = "Security group for web-server with HTTPS ports"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_app_cidr]
}

#
# Create a security group for SSH traffic
#
module "ssh_secure_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/ssh"

  name        = format("%s-ssh-%s", local.prefix, random_id.id.hex)
  description = "Security group for SSH ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_mgmt_cidr]
}

#
# Create BIG-IP
#
module bigip {
  source = "../../"

  prefix = format(
    "%s-bigip-3-nic_with_new_vpc-%s",
    local.prefix,
    random_id.id.hex
  )
  ec2_instance_type           = "m5.large"
  ec2_key_name                = var.ec2_key_name
  aws_secretmanager_secret_id = aws_secretsmanager_secret.bigip.id
  bigip_map                   = local.bigip_map
}
