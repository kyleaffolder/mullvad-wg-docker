#!/bin/bash

# Outputs external IP address in console

# HTTP
# externalIP=$(curl -s ifconfig.me)
# externalIP=$(curl -s http://ipecho.net/plain)
externalIP=$(curl -s http://whatismyip.akamai.com/) # fastest using HTTP
# externalIP=$(curl -s http://ifcfg.me/)
# externalIP=$(curl -s http://icanhazip.com/)

# HTTPS
# externalIP=$(curl -s https://ifcfg.me/) # fastest using HTTPS w/ a valid cert.
# externalIP=$(curl -s https://icanhazip.com/)

echo "The external IP address of this container is $externalIP"