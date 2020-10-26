terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    bigip = {
      source = "F5Networks/bigip"
      version = "1.4.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
  required_version = ">= 0.13"
}