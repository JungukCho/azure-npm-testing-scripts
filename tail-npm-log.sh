#!/bin/bash

NPMLOG="npm-log.txt"
kubectl logs -n kube-system -l k8s-app=azure-npm --tail -1 --prefix > $NPMLOG