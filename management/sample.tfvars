# terraform.tfvars

# General
cloud_type      = "aws"
network_name    = "sample"

# Cluster settings
cluster_index   = 0
controller_max  = 3
worker_max      = 3
ha_enabled      = true
backend_type    = s3

# AWS-specific settings
instance_type         = "t3.micro"
aws_credentials_file  = "aws_dev.ini"

kubernetes_version = "1.34.2"
coredns_version    = "1.31.1"
