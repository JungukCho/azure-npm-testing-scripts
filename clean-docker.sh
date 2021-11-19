#!/bin/bash

argc=$#

if [[ $argc -ne 1 ]]
then
	echo "[K8s CONFIG FILE] (e.g., aks-for-conformance.config.config)"
        exit -1
fi

CLUSTER_CONFIG_FILE=$1
CLUSTER_CONFIG_FILE_SUFFIX="config"
DOCKER_NAME=${CLUSTER_CONFIG_FILE%.$CLUSTER_CONFIG_FILE_SUFFIX}
echo "DOCKER_NAME:" $DOCKER_NAME
docker stop $DOCKER_NAME
docker rm $DOCKER_NAME
