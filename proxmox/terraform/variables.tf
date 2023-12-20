variable "k8s_domain" {
  type        = string
  description = "Input from environment variable"
}

variable "vm_ssh_user" {
  type = string
  description = "VM SSH user"
}

variable "pm_api_url" {
  type        = string
  description = "Input from environment variable"
}

variable "pm_node" {
  default = "pve"
}

variable "pm_api_token_id" {
  type        = string
  description = "Input from environment variable"
}

variable "pm_api_token_secret" {
  type        = string
  description = "Input from environment variable"
}

variable "pm_storage" {
  default = "data"
}

variable "pm_pool_name" {
  default = "K8s"
}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa.pub"
}
