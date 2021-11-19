#!/bin/bash
set -xv

argc=$#

if [[ $argc -ne 3 ]]
then
	echo "[K8s AKS CONFIG FILE] [e2e.test binary name without tar.gz] [only Tag of NPM image name]
     (e.g., aks-for-conformance.config, e2e.test.vamsi, ONLY last suffix - mcr.microsoft.com/containernetworking/azure-npm:<TAG>)"
	exit -1
fi

DOCKER_IMAGE="e2e-test-on-k8s"
CLUSTER_CONFIG_FILE=$1
CLUSTER_CONFIG_FILE_SUFFIX="config"
E2E_TEST_BINARY=$2
NPM_IMAGE=$3
CONFORMANCE_TEST_DIR="/root/test"
DOCKER_NAME=${CLUSTER_CONFIG_FILE%.$CLUSTER_CONFIG_FILE_SUFFIX}
DOCKER_NAME=${DOCKER_NAME##*/}
echo "DOCKER_NAME:" $DOCKER_NAME


# 1. Check whether docker image exists or not. 
# 1.1. If not exist, build docker image
docker images | grep ${DOCKER_IMAGE} || exit_code=$?
echo $exit_code
if [[ $exit_code -ne 0 ]]
then
    echo ${DOCKER_IMAGE} " Image does not exist. Start built it"
    docker build -t ${DOCKER_IMAGE} -f e2e-test-on-k8s.Dockerfile .
fi

# 1.2. Check whether this docker container is running or not.
# If so, appending index to create another docker container.
COUNT=1
NEW_DOCKER_NAME=${DOCKER_NAME}
while [[ true ]]
do

docker ps | grep ${NEW_DOCKER_NAME} || exit_code=$?
echo $exit_code

if [[ $exit_code -eq 0 ]]
then
    echo ${NEW_DOCKER_NAME} " is running now, which means one expr was already executed. Append number at end of docker name"
    NEW_DOCKER_NAME=$DOCKER_NAME-$COUNT
    echo $NEW_DOCKER_NAME, $COUNT

	if [[ $COUNT -eq 5 ]]
	then
    	    echo "Cannot make docker"
    	    exit -1
	fi
	COUNT=$((COUNT+1))
else
	echo ${NEW_DOCKER_NAME} " can be used"
	break
fi
done

DOCKER_NAME=${NEW_DOCKER_NAME}

# 2. start docker and create shared directory between host and docker container.
SHARED_DIR="/root/shared"
mkdir -p $(pwd)/shared
docker run -it -d -v $(pwd)/scripts:${SHARED_DIR} --name ${DOCKER_NAME} ${DOCKER_IMAGE} 

docker exec ${DOCKER_NAME} mkdir -p ${CONFORMANCE_TEST_DIR}


# 3. Setup conformance test
## 3.1 create conformance-test.sh and copy it into docker
CLUSTER_INFO=$(grep server ${CLUSTER_CONFIG_FILE})
FQDN=${CLUSTER_INFO##*//}
echo "FQDN:" ${FQDN} 

## create conformance-test.sh script
NPM_TEST="conformance-test.sh"
cat << EOF > ${NPM_TEST}
#!/bin/bash

kubectl cluster-info
kubectl get nodes -o wide

FQDN="FQDN_INFORMATION"
KUBERNETES_SERVICE_HOST="$FQDN" KUBERNETES_SERVICE_PORT=443 ./e2e.test --provider=local --ginkgo.focus="NetworkPolicy" --ginkgo.skip="SCTP" --kubeconfig=/root/.kube/config
EOF

sed -i "s/FQDN_INFORMATION/${FQDN}/" $(pwd)/${NPM_TEST}
docker cp ${NPM_TEST} ${DOCKER_NAME}:$CONFORMANCE_TEST_DIR
docker exec ${DOCKER_NAME} chmod +x $CONFORMANCE_TEST_DIR/${NPM_TEST} 

rm ${NPM_TEST}


## copy tail-npm-log.sh script
NPM_LOG_PRINT_HELPER="tail-npm-log.sh"
docker cp ${NPM_LOG_PRINT_HELPER} ${DOCKER_NAME}:$CONFORMANCE_TEST_DIR


## 3.2 create config and copy it into docker
KUBECONFIG_DIR="/root/.kube"
K8S_CONFIG="config"
docker exec ${DOCKER_NAME} mkdir -p ${KUBECONFIG_DIR} 
docker cp ${CLUSTER_CONFIG_FILE} ${DOCKER_NAME}:${KUBECONFIG_DIR}/${K8S_CONFIG}


## 3.3 copy e2e conformance binary
tar -xzvf ${E2E_TEST_BINARY}.tar.gz 
docker cp ${E2E_TEST_BINARY} ${DOCKER_NAME}:$CONFORMANCE_TEST_DIR/"e2e.test"
rm ${E2E_TEST_BINARY}


# 4. Set up azure-npm.yaml
NPM_YAML_TEMPLATE="azure-npm.yaml.template"
NPM_YAML="azure-npm.yaml"
cp ${NPM_YAML_TEMPLATE} ${NPM_YAML}
echo $NPM_IMAGE
sed -i "s/NPM_IMAGE/${NPM_IMAGE}/" $(pwd)/${NPM_YAML} 
docker cp ${NPM_YAML} ${DOCKER_NAME}:$CONFORMANCE_TEST_DIR/
rm ${NPM_YAML}
 
# 5. Setup cyclonous
CYCLONUS_TEST_DIR="/root/test/cyclonus"
docker exec ${DOCKER_NAME} mkdir -p ${CYCLONUS_TEST_DIR}

## 5.1 create cyclonus_job.yaml
CYCLONOUS_JOB_YAML="cyclonus_job.yaml"
cat << EOF > ${CYCLONOUS_JOB_YAML}
apiVersion: batch/v1
kind: Job
metadata:
  name: cyclonus
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - command:
            - ./cyclonus
            - generate
            - --noisy=true
            - --ignore-loopback=true
            - --cleanup-namespaces=true
            - --perturbation-wait-seconds=5
            - --pod-creation-timeout-seconds=30
            - --job-timeout-seconds=2
            - --server-protocol=TCP,UDP
              #- --verbosity=debug
              #- --include=direction, end-port, ingress, egress, numbered-port, port, protocol, tcp, udp
          name: cyclonus
          imagePullPolicy: Always
          image: mfenwick100/cyclonus:v0.4.7
          #image: mfenwick100/cyclonus:latest
      serviceAccount: cyclonus
EOF

## 5.2. create cyclonus-script.sh
CYCLONOUS_SCRIPT="cyclonus-script.sh"
cat << EOF > ${CYCLONOUS_SCRIPT}
#!/bin/bash
ARGC=\$#

if [[ \$ARGC -ne 1 ]]
then
        echo "[start, cleanup]"
        exit -1
fi

COMMAND=\$1
echo \$COMMAND

case \$COMMAND in
"start")
        echo "start running cyclonus"
        JOB_NS="netpol"
        JOB_NAME="job.batch/cyclonus"
        kubectl create ns netpol
        kubectl create clusterrolebinding cyclonus --clusterrole=cluster-admin --serviceaccount=netpol:cyclonus
        kubectl create sa cyclonus -n netpol
        kubectl create -f cyclonus_job.yaml -n netpol

        # wait for job to start running
        # TODO there's got to be a better way to do this
        sleep 30
        kubectl get all -A

        kubectl wait --for=condition=ready pod -l job-name=cyclonus -n \$JOB_NS --timeout=5m
        kubectl logs -f -n \$JOB_NS \$JOB_NAME
        ;;
"cleanup")
        echo "cleanup"
        kubectl delete -f cyclonus_job.yaml -n netpol
        kubectl delete ns netpol x y z
        ;;
*)
        echo "Unknown command: ", \$COMMAND
esac
EOF

docker cp ${CYCLONOUS_JOB_YAML} ${DOCKER_NAME}:$CYCLONUS_TEST_DIR/
docker cp ${CYCLONOUS_SCRIPT} ${DOCKER_NAME}:$CYCLONUS_TEST_DIR/
docker exec ${DOCKER_NAME} chmod +x $CYCLONUS_TEST_DIR/cyclonus-script.sh 

rm ${CYCLONOUS_JOB_YAML}
rm ${CYCLONOUS_SCRIPT}

docker exec -it ${DOCKER_NAME} bash
echo "Docker name: " ${DOCKER_NAME}