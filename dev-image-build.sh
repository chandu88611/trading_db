#!/bin/bash
# This script will create and push docker img

# declare -r username="fusion_fusion"
# declare -r password="fusion_fusion@123"
declare -r image_tag="ligato-postgres:latest"

## docker login
# docker login -u $username -p $password
# echo "Login done"

## Build images
# --network host - required for installing pcks using local network
docker build -t $image_tag --network host .
echo "docker img build worked"

## check the available docker images
docker images
echo "shown the available docker images"

## Disable the firewall
# iptables -F

## PUSH the built images
# docker image push $image_tag
# echo "pushed the built images"

echo "************** End of Image Build Script ***************"