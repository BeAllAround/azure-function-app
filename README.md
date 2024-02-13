# azure-function-app - zip and deploy HTTP azure functions using terraform

Terraform configuration for zipping and deploying HTTP Azure Function Apps

| ![Voxgig](https://www.voxgig.com/res/img/vgt01r.png) | This open source module is sponsored and supported by [Voxgig](https://www.voxgig.com). |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------- |

## Requirements

- Active Azure Subscription
- Terraform CLI
- Azure CLI: https://learn.microsoft.com/en-us/cli/azure


## Quick Example

```hcl

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
  }
}

module "function_function" {
  source     = "./tf/modules/function"
  # must depend on a resource as to deploy in order
  depends_on = [ azurerm_windows_function_app.function_app ]

  for_each = var.azure_functions

  name         = each.key
  json_content = each.value.content
}

# azure function host file config
resource "local_file" "hostfile" {
  depends_on = [ module.function_function ]
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
  folders_to_zip       = join(" ", [ "src", "node_modules" ]) # folders to zip up for deployment
  publish_code_command = <<EOT
    zip -r -q -o backend.zip ${local.files_to_zip} host.json ${local.folders_to_zip} &&
    rm ${local.files_to_zip} -rf &&
    az functionapp deployment source config-zip -g ${azurerm_resource_group.resource.name} -n ${azurerm_windows_function_app.function_app.name} --src backend.zip
  EOT
}

```

## Steps to deploy

1. https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure
2. Preferably, set up variables in `variables.tf` file
3. Initialize Terraform: `terraform init -upgrade`
4. Plan the deployment: `terraform plan`
5. Apply the changes: `terraform apply`
