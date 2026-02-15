locals {
  use_artifacts_source   = var.artifacts_organization != ""
  use_filesystem_source  = !local.use_artifacts_source
  create_storage_account = local.use_filesystem_source || var.enable_file_logging

  container_image = "${var.container_registry}/${var.container_repository}:${var.image_tag}"

  extension_mount_path = "/data/extensions"
  logs_mount_path      = "/data/logs"
  location             = "uksouth"
}
