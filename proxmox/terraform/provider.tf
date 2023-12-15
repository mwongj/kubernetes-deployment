terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_log_enable     = false
  pm_log_file       = "terraform-plugin-proxmox.log"
  pm_debug	    = false
  pm_log_levels     = {
    _default	    = "debug"
  }

  pm_parallel       = 1
  pm_tls_insecure   = true
  pm_api_url        = var.pm_api_url
  pm_api_token_id   = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}
