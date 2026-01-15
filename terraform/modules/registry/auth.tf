# creating auth file in a container to avoid installing htpasswd on an existing host

locals {
  registry_user = "admin"
}

#resource "random_password" "registry_pass" {
#  length    = 24
#  special   = true
#}

# shared volume to hold auth file
resource "docker_volume" "registry_auth" {
  name = "registry_auth"
}

# image that has htpasswd tool
resource "docker_image" "httpd" {
  name  = "httpd:2.4-alpine"
}

resource "docker_container" "make_htpasswd" {
  name    = "make-htpasswd"
  image   = docker_image.httpd.image_id

  # mount the volume
  volumes {
    volume_name       = docker_volume.registry_auth.name
    container_path    = "/out"
  }

  # run htpasswd and exit
  entrypoint    = ["/bin/sh", "-c"]
  command       = ["htpasswd -Bbn \"$REGISTRY_USER\" \"$REGISTRY_PASS\" > /out/htpasswd"]

  env = [
    "REGISTRY_USER=${local.registry_user}",
    "REGISTRY_PASS=${var.registry_pass}",
  ]

  # exit
  must_run  = false
  restart   = "no"
}
