resource "random_bytes" "kubernetes_encryption_key" {
  length = 32
}
