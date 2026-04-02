terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.60.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "terraformrg"
    storage_account_name = "terraformstoragefe832e63"
    container_name       = "terraform"
    key                  = "tf-vscodeprivatemktplace.tfstate"
    use_oidc             = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.resource_name_suffix}"
  location = local.location
}

resource "azurerm_log_analytics_workspace" "la" {
  name                = "law-${var.resource_name_suffix}"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_analytics_daily_quota_gb
}

resource "azurerm_application_insights" "ai" {
  name                = "appin-${var.resource_name_suffix}"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.la.id
  application_type    = "web"
}

resource "azurerm_storage_account" "sa" {
  #checkov:skip=CKV_AZURE_190: testing
  #checkov:skip=CKV2_AZURE_47: testing
  #checkov:skip=CKV2_AZURE_33: testing
  #checkov:skip=CKV2_AZURE_1: testing
  #checkov:skip=CKV2_AZURE_38: testing
  #checkov:skip=CKV2_AZURE_41: testing
  #checkov:skip=CKV2_AZURE_40: testing
  #checkov:skip=CKV_AZURE_33: testing
  #checkov:skip=CKV_AZURE_206: testing
  #checkov:skip=CKV_AZURE_44: testing
  #checkov:skip=CKV_AZURE_59: testing
  name                     = "stvscodeprivatemktplce"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "extensions" {
  name               = "extensions"
  storage_account_id = azurerm_storage_account.sa.id
  quota              = 5
}

resource "azurerm_storage_share" "logs" {
  name               = "logs"
  storage_account_id = azurerm_storage_account.sa.id
  quota              = 5
}


resource "azurerm_user_assigned_identity" "identity" {
  count               = local.use_artifacts_source ? 1 : 0
  name                = "uai-${var.resource_name_suffix}"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${var.resource_name_suffix}"
  location                   = local.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.la.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app_environment_storage" "extensions" {
  name                         = "extensions"
  container_app_environment_id = azurerm_container_app_environment.env.id
  account_name                 = azurerm_storage_account.sa.name
  share_name                   = azurerm_storage_share.extensions.name
  access_key                   = azurerm_storage_account.sa.primary_access_key
  access_mode                  = "ReadOnly"
}

resource "azurerm_container_app_environment_storage" "logs" {
  name                         = "logs"
  container_app_environment_id = azurerm_container_app_environment.env.id
  account_name                 = azurerm_storage_account.sa.name
  share_name                   = azurerm_storage_share.logs.name
  access_key                   = azurerm_storage_account.sa.primary_access_key
  access_mode                  = "ReadWrite"
}


resource "azurerm_container_app" "app" {
  name                         = "ca-${var.resource_name_suffix}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  dynamic "identity" {
    for_each = local.use_artifacts_source ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.identity[0].id]
    }
  }

  template {
    container {
      name   = "vscode-private-marketplace"
      image  = local.container_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.ai.connection_string
      }
      env {
        name  = "Marketplace__Logging__LogToConsole"
        value = "true"
      }

      # Filesystem extension source
      env {
        name  = "Marketplace__ExtensionSourceDirectory"
        value = "/data/extensions"
      }

      # Logs directory
      env {
        name  = "Marketplace__LogsDirectory"
        value = "/data/logs"
      }

      env {
        name  = "Marketplace__Upstreaming__Mode"
        value = "none"
      }

      # Mount extensions share
      volume_mounts {
        name = "extensions"
        path = "/data/extensions"
      }

      # Mount logs share
      volume_mounts {
        name = "logs"
        path = "/data/logs"
      }
    }

    # Extensions volume
    volume {
      name         = "extensions"
      storage_name = azurerm_container_app_environment_storage.extensions.name
      storage_type = "AzureFile"
    }

    # Logs volume
    volume {
      name         = "logs"
      storage_name = azurerm_container_app_environment_storage.logs.name
      storage_type = "AzureFile"
    }


    min_replicas = 1
    max_replicas = 1
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  registry {
    server               = var.container_registry
    username             = var.container_registry_username
    password_secret_name = "registry-password"
  }

  secret {
    name  = "registry-password"
    value = var.container_registry_password
  }
}

output "container_app_url" {
  value = "https://${azurerm_container_app.app.latest_revision_fqdn}/"
}

output "extension_source_type" {
  value = local.use_artifacts_source ? "Artifacts" : "FileSystem"
}

output "client_id" {
  value = local.use_artifacts_source ? azurerm_user_assigned_identity.identity[0].client_id : null
}
