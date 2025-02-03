resource "random_bytes" "kubernetes_encryption_key" {
  length = 32
}

resource "local_file" "kubernetes_encryption_config" {
  filename = "${local.ansible_file_path}/encryption-config.yaml"
  content = <<EOT
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: ${random_bytes.kubernetes_encryption_key.base64}
    - identity: {}
EOT

}
