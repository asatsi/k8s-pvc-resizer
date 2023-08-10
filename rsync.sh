#!/bin/bash

echo hello world

if [ -z $SOURCE_PVC ] || [ -z $TARGET_PVC ]; then
	echo Nothing to do.
	exit 1
fi

echo "Good thing: both SOURCE_PVC and TARGET_PVC are defined!"
echo "SOURCE_PVC: [$SOURCE_PVC]"
echo "TARGET_PVC: [$TARGET_PVC]"
echo "rsync beginning...."
rsync -av --progress --stats $SOURCE_PVC $TARGET_PVC

echo "Done with rsync - now sleeping forever unless you kill me!"
while true
do
sleep 1000
done
