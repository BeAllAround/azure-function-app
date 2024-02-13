terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.87.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.2"
    }
  }

  required_version = "~> 1.6.6"
}
