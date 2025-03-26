# create a ssh key to use when creating kubernetes hosts
resource "tls_private_key" "kubernetes_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kubernetes_ssh_key" {
  key_name    = "kubernetes_ssh_key-${var.cluster_index}"
  public_key  = tls_private_key.kubernetes_ssh_key.public_key_openssh
}
