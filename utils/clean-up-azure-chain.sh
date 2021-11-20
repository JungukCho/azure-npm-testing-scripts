#!/bin/bash

# delete azure in forward
iptables -L FORWARD --line-numbers
iptables -D FORWARD 3
iptables -w 60 -X AZURE-NPM
iptables -nvL


# delete ipset. Normally there are only azure-npm ipset
ipsets=$(ipset list | grep Name | awk '{print $2}')
# Just iterate multiple times. (Not deterministic way)
count=0
while [[ $count -le 5 ]]
do 
    for ipset in ${ipsets[@]}
    do
        ipset -X $ipset
    done
    count=$((count+1))
done