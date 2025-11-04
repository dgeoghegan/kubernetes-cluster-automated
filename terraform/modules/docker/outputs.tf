output "docker_server_public_ip" {
  value = aws_instance.docker_server[0].public_ip
}
