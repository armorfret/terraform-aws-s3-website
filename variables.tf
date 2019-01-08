variable "logging-bucket" {
  type = "string"
}

variable "file-bucket" {
  type = "string"
}

variable "redirect-bucket" {
  type = "string"
}

variable "root-domain" {
  type = "string"
}

variable "redirect-domains" {
  type    = "list"
  default = []
}

variable "tls-level" {
  type    = "string"
  default = "TLSv1.2_2018"
}

variable "error-document" {
  type    = "string"
  default = "404.html"
}
