resource "docker_volume" "registry_data" {
  name = "registry_data"
}

# Pull registry image
resource "docker_image" "container_registry" {
  name  = "registry:2"
}

# Run registry container
resource "docker_container" "container_registry" {
  name  = "registry"
  image = docker_image.container_registry.image_id
  restart = "always"
  ports {
    internal  = 5000
    external  = 5000
    ip        = "0.0.0.0" # accessible from everywhere
  }

  # enable auth via htpasswd
  env = [
    "REGISTRY_AUTH=htpasswd",
    "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm",
    "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd",
    "REGISTRY_HTTP_SECRET=${var.registry_pass}",
    "REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/var/lib/registry",
    "REGISTRY_HTTP_ADDR=:5000",
#    "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/tls.crt",
#    "REGISTRY_HTTP_TLS_KEY=/certs/tls.key",
  ]

  volumes {
    volume_name     = docker_volume.registry_data.name
    container_path  = "/var/lib/registry"
  }

  volumes {
    volume_name     = docker_volume.registry_auth.name
    container_path  = "/auth"
    read_only       = true
  }

#  volumes {
#    volume_name     = docker_volume.registry_tls.name
#    container_path  = "/certs"
#    read_only       = true
#  }

  healthcheck {
    test          = ["CMD-SHELL", "nc -z 127.0.0.1:5000"]
    interval      = "30s"
    timeout       = "3s"
    retries       = 3
    start_period  = "5s"
  }

# ensure htpasswd file exists before creating registry
  depends_on  = [
    docker_container.make_htpasswd,
#    docker_container.make_tls
  ]

  lifecycle {
    ignore_changes = [
      image,
      command,
      hostname,
      labels,
      ports,
      start,
      env,
    ]
  }
}
