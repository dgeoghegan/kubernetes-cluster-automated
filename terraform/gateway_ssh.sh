#!/bin/bash
ssh ubuntu@$(terraform output | grep "ssh_gateway" | cut -d "\"" -f 2) -i $(cat aws_credentials.tf | grep ssh_gateway -A 1 | grep public_key | cut -f 2 -d "\"" | sed 's/\.pub//')
