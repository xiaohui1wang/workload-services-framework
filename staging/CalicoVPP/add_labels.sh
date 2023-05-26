#!/bin/bash

nodes=$(kubectl get node | grep -v "NAME" | awk '{print $1}')

for n in $nodes; do
   kubectl label nodes $n HAS-SETUP-CALICO-VPP-VCL=yes 
done
