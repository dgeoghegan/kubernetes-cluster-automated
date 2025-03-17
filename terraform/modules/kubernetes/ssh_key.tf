# create a ssh key to use when creating kubernetes hosts
resource "tls_private_key" "kubernetes_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "kubernetes_ssh_key" {
  filename = "${local.ansible_file_path}/kubernetes_ssh_key"
  content = tls_private_key.kubernetes_ssh_key.private_key_openssh
  file_permission = "0400"
}


resource "aws_key_pair" "kubernetes_ssh_key" {
  key_name    = "kubernetes_ssh_key"
  public_key  = tls_private_key.kubernetes_ssh_key.public_key_openssh
}
