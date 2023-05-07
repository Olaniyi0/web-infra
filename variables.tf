variable "instance_type" {
    description = "virtual machine instance type"
    type = string
    default = "Standard_B1ls"
}

variable "os_image_publisher" {
  description = "OS image publisher"
  type = string
  default = "Canonical"
}

variable "os_image_offer" {
  description = "OS image offer"
  type = string
  default = "0001-com-ubuntu-server-jammy"
}

variable "os_image_sku" {
  description = "OS image sku"
  type = string
  default = "22_04-lts-gen2"
}

variable "backend_storage_name" {
  description = "container to store terraform backend"
  type = string
  default = "tf-backend"
}