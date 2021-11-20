#!/bin/bash

DATE=$(date "+%F-%H-%M-%S")
NPMLOG="npm-log.txt"
kubectl logs -n kube-system -l k8s-app=azure-npm --tail -1 --prefix > $DATE-$NPMLOG