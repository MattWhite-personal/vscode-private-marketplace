variable "container_registry_username" {
  type = string
  default = "test-admin"
}

variable "container_registry_password" {
  type      = string
  sensitive = true
}

variable "image_tag" {
  type    = string
  default = "1.0.57"
}

variable "resource_name_suffix" {
  type    = string
  default = "vscode-privatemktplce"
}

variable "location" {
  type = string
}

variable "container_registry" {
  type    = string
  default = "mcr.microsoft.com"
}

variable "container_repository" {
  type    = string
  default = "vsmarketplace/vscode-private-marketplace"
}

variable "organization_name" {
  type    = string
  default = ""
}

variable "artifacts_organization" {
  type    = string
  default = ""
}

variable "artifacts_project" {
  type    = string
  default = ""
}

variable "artifacts_feed" {
  type    = string
  default = ""
}

variable "enable_file_logging" {
  type    = bool
  default = false
}

variable "enable_console_logging" {
  type    = bool
  default = false
}

variable "ip_allow_list" {
  type    = list(string)
  default = []
}

variable "vnet_traffic_only" {
  type    = bool
  default = false
}

variable "log_analytics_daily_quota_gb" {
  type    = number
  default = 1
}

variable "disabled_feature_flags" {
  type    = list(string)
  default = []
}
