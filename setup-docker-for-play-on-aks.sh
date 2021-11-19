#!/bin/bash
set -xv

argc=$#

if [[ $argc -ne 2 ]]
then
	echo "[K8s CONFIG FILE] [aks name]"
	exit -1
fi

DOCKER_IMAGE="e2e-test-on-k8s"
CLUSTER_CONFIG_FILE=$1
DOCKER_NAME=$2
echo "DOCKER_NAME:" $DOCKER_NAME


# 1. Check whether docker image exists or not. 
# 1.1. If the docker image does not exist, build docker image.
docker images | grep ${DOCKER_IMAGE} || exit_code=$?
echo $exit_code
if [[ $exit_code -ne 0 ]]
then
    echo ${DOCKER_IMAGE} " Image does not exist. Start built it"
    docker build -t ${DOCKER_IMAGE} -f e2e-test-on-k8s.Dockerfile .
fi

# 1.2. Check whether this docker container is running or not.
# If so, stop running this script since it means one expr is already running
docker ps | grep ${DOCKER_NAME} || exit_code=$?
echo $exit_code
if [[ $exit_code -eq 0 ]]
then
    echo ${DOCKER_NAME} " is running now, which means one expr was already executed. Stop running this script"
    exit -1
fi

# 2. start docker and create shared directory between host and docker container.
SHARED_DIR="/root/shared"
mkdir -p $(pwd)/shared
docker run -it -d -v $(pwd)/scripts:${SHARED_DIR} --name ${DOCKER_NAME} ${DOCKER_IMAGE} 

## 3.2 create config and copy it into docker
K8_CONFIG="config"
KUBECONFIG_DIR="/root/.kube/"
docker exec ${DOCKER_NAME} mkdir -p ${KUBECONFIG_DIR} 
docker cp ${K8_CONFIG} ${DOCKER_NAME}:${KUBECONFIG_DIR}

docker exec -it ${DOCKER_NAME} bash
echo "Docker name: " ${DOCKER_NAME}