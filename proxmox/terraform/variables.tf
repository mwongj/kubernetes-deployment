variable "pm_api_url" {
  default = "https://pve.wongway.io/api2/json"
}

variable "pm_node" {
  default = "pve"
}

variable "pm_api_token_id" {
  type	  = string
  description = "Input from environment variable"
}

variable "pm_api_token_secret" {
  type		= string
  description   = "Input from environment variable"
}

variable "pm_storage" {
  default = "data"
}

variable "pm_pool" {
  default = "K8s"
}

#variable "pm_user" {
#  default = ""
#}

#variable "pm_password" {
#  default = ""
#}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa.pub"
}
