provider "azurerm" {
  skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

resource "azurerm_resource_group" "resource" {
  name     = "res02test"
  location = var.azure_region
}

resource "azurerm_storage_account" "storage" {
  name                     = "testdev01"
  depends_on               = [azurerm_resource_group.resource]
  resource_group_name      = azurerm_resource_group.resource.name
  location                 = azurerm_resource_group.resource.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_app_service_plan" "service_plan" {
  name                = "testdev01"
  depends_on          = [azurerm_storage_account.storage]
  resource_group_name = azurerm_resource_group.resource.name
  location            = azurerm_resource_group.resource.location
  kind                = "elastic"

  sku {
    tier = "ElasticPremium"
    size = "EP1"
  }
}

resource "azurerm_application_insights" "app_insights" {
  name                = "testdev01"
  depends_on          = [azurerm_app_service_plan.service_plan]
  resource_group_name = azurerm_resource_group.resource.name
  location            = azurerm_resource_group.resource.location
  application_type    = "Node.JS"
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "testdev01"
  depends_on          = [azurerm_application_insights.app_insights]
  location            = azurerm_resource_group.resource.location
  resource_group_name = azurerm_resource_group.resource.name
  offer_type          = "Standard"
  # kind                = "NoSQL"

  lifecycle {
    prevent_destroy = true
  }

  enable_automatic_failover = true

  capacity {
    total_throughput_limit = -1
  }

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = "westeurope"
    failover_priority = 0
  }
}

variable "windows_function_app_name" {
  type    = string
  default = "testdev01"
}

resource "azurerm_windows_function_app" "function_app" {
  depends_on = [azurerm_cosmosdb_account.db]

  name                = var.windows_function_app_name
  resource_group_name = azurerm_resource_group.resource.name
  location            = azurerm_resource_group.resource.location

  service_plan_id = azurerm_app_service_plan.service_plan.id

  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME     = "node"
    WEBSITE_NODE_DEFAULT_VERSION = "~18"
    WEBSITE_RUN_FROM_PACKAGE     = "1"
    FUNCTIONS_WORKER_RUNTIME     = "node"
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.app_insights.instrumentation_key
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = azurerm_storage_account.storage.primary_connection_string
    AZURE_CONNSTR_BLOB_CONNECTION_STRING   = azurerm_storage_account.storage.primary_connection_string
    AZURE_CONNSTR_COSMOS_CONNECTION_STRING = azurerm_cosmosdb_account.db.connection_strings[0]
    WEBSITE_CONTENTSHARE                   = var.windows_function_app_name
  }

  site_config {
    application_stack {
      node_version = "~16"
    }
    cors {
      allowed_origins = [
        "https://portal.azure.com"
      ]
    }
  }

}

variable "azure_functions" {
  type = any
  default = {
    hello = {
      name = "hello"
      content = {
        "bindings" = [
          {
            "authLevel" = "anonymous"
            "direction" = "in"
            "route"     = "hello"
            "methods" = [
              "get",
              "post"
            ]
            "name" = "req"
            "type" = "httpTrigger"
          },
          {
            "direction" = "out"
            "name"      = "res"
            "type"      = "http"
          },
        ],

        "entryPoint" = "handler",
        "scriptFile" = "../src/handlers/hello.js"

      }
    }

    goodbye = {
      name = "goodbye"
      content = {
        "bindings" = [
          {
            "authLevel" = "anonymous"
            "direction" = "in"
            "route"     = "goodbye"
            "methods" = [
              "get",
              "post"
            ]
            "name" = "req"
            "type" = "httpTrigger"
          },
          {
            "direction" = "out"
            "name"      = "res"
            "type"      = "http"
          },
        ],

        "entryPoint" = "handler",
        "scriptFile" = "../src/handlers/goodbye.js"
      }
    }
  }
}

module "function_function" {
  source     = "./tf/modules/function"
  depends_on = [azurerm_windows_function_app.function_app]

  for_each = var.azure_functions

  name         = each.key
  json_content = each.value.content
}

resource "local_file" "hostfile" {
  depends_on = [module.function_function]
  content = jsonencode(
    {
      "version" = "2.0",
      "extensionBundle" = {
        "id"      = "Microsoft.Azure.Functions.ExtensionBundle",
        "version" = "[4.*, 5.0.0)"
      }
    }
  )
  filename = "host.json"

}

locals {
  files_to_zip         = join(" ", keys(var.azure_functions))
  folders_to_zip       = join(" ", [ "src" ])
  publish_code_command = <<EOT
    zip -r -q -o backend.zip ${local.files_to_zip} host.json ${local.folders_to_zip} &&
    rm ${local.files_to_zip} -rf &&
    az functionapp deployment source config-zip -g ${azurerm_resource_group.resource.name} -n ${azurerm_windows_function_app.function_app.name} --src backend.zip
  EOT
  # az functionapp deployment source config-zip -g ${azurerm_resource_group.resource.name} -n ${azurerm_windows_function_app.function_app.name} --src backend.zip

  # publish_code_command = "echo 'deploying...'"
}

resource "null_resource" "function_app_publish" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }

  depends_on = [
    local_file.hostfile,
    module.function_function,
    local.publish_code_command,
    azurerm_windows_function_app.function_app
  ]

  triggers = {
    always_run = "${timestamp()}"
  }
}
