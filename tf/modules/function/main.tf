
variable "name" {
  type = string
  default = "function"
}

variable "json_content" { 
  type = any
}

resource "null_resource" "always_run" {
  triggers = {
    timestamp = "${timestamp()}"
  }
}

resource "local_file" "function" {
  depends_on = [ null_resource.always_run ]
  content = jsonencode(var.json_content)
  filename = "${var.name}/function.json"
  lifecycle {
    replace_triggered_by = [
      null_resource.always_run
    ]
  }

}
