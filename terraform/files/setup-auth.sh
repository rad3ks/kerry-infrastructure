#!/bin/bash
# Install apache2-utils for htpasswd utility
apt-get update
apt-get install -y apache2-utils

# Create password file
htpasswd -bc /etc/nginx/.htpasswd ${staging_username} ${staging_password} 