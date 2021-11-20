#!/bin/bash

DATE=$(date "+%F-%H-%M-%S")
LOGFILE="top-pod.log"
while [[ true ]]
do
    kubectl top pods -n kube-system >> $DATE-$LOGFILE
    echo " " >> $LOGFILE
    echo " " >> $LOGFILE
    sleep 1
done