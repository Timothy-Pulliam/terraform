terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.70.0"
    }
  }
  backend "s3" {
    bucket = "tpulliam-terraform-files"
    key    = "project1/terraform.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {
  # Configuration options
  region = var.region
}



variable "region" {
  type = string
  description = "region where the VPC should be deployed"
  default = "us-east-1"
}

variable "vpc_name" {
  type    = string
  default = "test_vpc"
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "num_azs" {
  type = number
  description = "number of availability zones the VPC is spread across"
  default = 2

  validation {
    condition     = var.num_azs != 2 || var.num_azs != 4
    error_message = "The VPC can only be split across 2 or 4 Availability Zones."
  }
}

locals {
  description = "list of availability zones"
  suffixes = ["a", "b", "c", "d"]

  azs = slice([for s in local.suffixes : "${var.region}${s}"], 0, var.num_azs)
  subnets = (var.num_azs == 2 ? cidrsubnets(var.vpc_cidr, 2, 2, 3, 3, 4, 4) : cidrsubnets(var.vpc_cidr, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5))
}


resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  instance_tenancy = "default"

  // If both attributes are enabled, an instance launched into the 
  // VPC receives a public DNS hostname if it is assigned a 
  // public IPv4 address or an Elastic IP address at creation.
  enable_dns_support = true
  enable_dns_hostnames = false

  tags = {
    // vpc name
    Name = var.vpc_name
    env = "test"
  }
}

// Internet Gateway is required to allow internet traffic to your vpc
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name} igw"
  }
}

resource "aws_subnet" "privateSubnet1A" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[0] //"10.0.0.0/18"
  availability_zone = local.azs[0]

  tags = {
    Name = "privateSubnet1A"
  }
}

resource "aws_subnet" "privateSubnet2A" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[1] //"10.0.64.0/18"
  availability_zone = local.azs[1]

  tags = {
    Name = "privateSubnet2A"
  }
}

resource "aws_subnet" "publicSubnet1" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[2] //"10.0.128.0/19"
  availability_zone = local.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "publicSubnet1"
  }
}

resource "aws_subnet" "publicSubnet2" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[3] //"10.0.160.0/19"
  availability_zone = local.azs[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "publicSubnet2"
  }
}

resource "aws_subnet" "privateSubnet1B" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[4] //"10.0.192.0/20"
  availability_zone = local.azs[0]

  tags = {
    Name = "privateSubnet1B"
  }
}

resource "aws_subnet" "privateSubnet2B" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = local.subnets[5] //"10.0.208.0/20"
  availability_zone = local.azs[1]

  tags = {
    Name = "privateSubnet2B"
  }
}

resource "aws_eip" "nat_eip1" {
  vpc      = true

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip" "nat_eip2" {
  vpc      = true

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat1" {
  allocation_id = aws_eip.nat_eip1.id
  subnet_id     = aws_subnet.publicSubnet1.id

  tags = {
    Name = "${var.vpc_name} NAT gw 1"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat2" {
  allocation_id = aws_eip.nat_eip2.id
  subnet_id     = aws_subnet.publicSubnet2.id

  tags = {
    Name = "${var.vpc_name} NAT gw 2"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "association1" {
  subnet_id      = aws_subnet.publicSubnet1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "association2" {
  subnet_id      = aws_subnet.publicSubnet2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.us-east-1.s3"

  tags = {
    Environment = "test"
  }
}

