#!/bin/bash

sudo accel-config disable-device dsa2
sudo accel-config config-device dsa2
sudo accel-config config-engine dsa2/engine2.0 --group-id=0
sudo accel-config config-engine dsa2/engine2.1 --group-id=0
sudo accel-config config-engine dsa2/engine2.2 --group-id=0
sudo accel-config config-engine dsa2/engine2.3 --group-id=0
sudo accel-config config-wq dsa2/wq2.0 --group-id=0 --wq-size=32 --priority=1 --block-on-fault=1 --type=user --name=wq0 --mode=dedicated --max-batch-size=1024 --max-transfer-size=2097152
sudo accel-config enable-device dsa2
sudo accel-config enable-wq dsa2/wq2.0
sudo accel-config list
