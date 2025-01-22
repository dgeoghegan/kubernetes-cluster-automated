#!/bin/bash
ssh ubuntu@$(terraform output | cut -d "\"" -f 2) -i $(cat aws_credentials.tf | grep public_key | cut -f 2 -d "\"" | sed 's/\.pub//')
