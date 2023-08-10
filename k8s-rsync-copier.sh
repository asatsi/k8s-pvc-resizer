#!/usr/bin/bash

if [ -z $3 ]; then
echo "ERROR: invalid parameters"
echo "Usage: "
echo "$0 <k8s namespace> <source pvc> <size of new pvc in GB>"
echo "Make sure the <source pvc> is not in use by any running POD"
echo "e.g. $0 integrations kafka-datadir-0 4"
exit
fi

k8s_namespace=$1
k8s_source_pvc=$2
k8s_new_size=$3
k8s_target_pvc=resize-$k8s_source_pvc
error_flagged=0
workdir=`pwd`/workdir/$k8s_source_pvc

# Validate both PVCs must exist
SOURCE_EXISTS=`kubectl -n $k8s_namespace --insecure-skip-tls-verify describe pvc $k8s_source_pvc 2> /dev/null`
if [ "$SOURCE_EXISTS" ]; then
  echo -n
  # echo "INFO: Source PVC [$k8s_source_pvc] does exist.......... [OK]"
else
  echo "ERROR: Source PVC [$k8s_source_pvc] does not exist......[BAD!]"
  error_flagged=1
fi

TARGET_EXISTS=`kubectl -n $k8s_namespace --insecure-skip-tls-verify describe pvc $k8s_target_pvc 2> /dev/null`
if [ "$TARGET_EXISTS" ]; then
  echo "ERROR: Target PVC [$k8s_target_pvc] does exist. The script will create config yamls for target pvc creation."
  error_flagged=1
else
  # echo "INFO: Target PVC [$k8s_target_pvc] does not exist.......[OK]"
  echo -n
fi

if [ $error_flagged == 1 ];then
  echo "ERROR: Exitting..."
  exit
fi

IS_SOURCE_USED=`kubectl -n $k8s_namespace --insecure-skip-tls-verify describe pvc $k8s_source_pvc 2> /dev/null | grep "Used By" `
if [ "$IS_SOURCE_USED" ]; then
  if [[ "$IS_SOURCE_USED" =~ .*"none".* ]]; then
    echo -n
    # echo "INFO: Source PVC $k8s_source_pvc is not being used.....[OK]"
  else
    echo "ERROR: Source PVC [$k8s_source_pvc] $IS_SOURCE_USED"
    error_flagged=1
  fi
fi

IS_TARGET_USED=`kubectl -n $k8s_namespace --insecure-skip-tls-verify describe pvc $k8s_target_pvc 2> /dev/null | grep Used\ By `
if [ "$IS_TARGET_USED" ]; then
  if [[ "$IS_TARGET_USED" =~ .*"none".* ]]; then
    # echo "INFO: Target PVC $k8s_target_pvc is not being used.....[OK]"
    echo -n
  else
    echo "ERROR: Target PVC [$k8s_target_pvc] $IS_TARGET_USED"
    error_flagged=1
  fi
fi

if [ $error_flagged == 1 ]; then
   echo exitting due to errors...
   exit
fi

echo "INFO: Creating phase1 and phase2 manifest files in directory "$workdir""
mkdir -p $workdir/phase1
cd $workdir/phase1

cp ../../../templates/pvc.yaml $k8s_target_pvc-pvc.yaml
sed -i "s#XX_1_XXGi#${k8s_new_size}Gi#g" $k8s_target_pvc-pvc.yaml
sed -i "s#pvc-rsync-copier#${k8s_target_pvc}#g" $k8s_target_pvc-pvc.yaml
sed -i "s#XXX_NAMESPACE_XXX#${k8s_namespace}#g" $k8s_target_pvc-pvc.yaml

cp ../../../templates/rsync.yaml $k8s_target_pvc-rsync.yaml
sed -i "s#XXX_SOURCE_PVC_XXX#${k8s_source_pvc}#g" $k8s_target_pvc-rsync.yaml
sed -i "s#XXX_TARGET_PVC_XXX#${k8s_target_pvc}#g" $k8s_target_pvc-rsync.yaml
sed -i "s/pvc-rsync-copier-deployment-name/rsync-${k8s_target_pvc}/g" $k8s_target_pvc-rsync.yaml

echo "INFO: Phase1: manifests created in workdir:" `pwd`
ls -l $k8s_target_pvc-pvc.yaml
ls -l $k8s_target_pvc-rsync.yaml

cd ../../..
echo 'INFO: Creating temporary directory to copy manifest files "workdir/phase2"'
mkdir -p $workdir/phase2
cd $workdir/phase2

cp ../../../templates/pvc.yaml $k8s_target_pvc-pvc.yaml
sed -i "s#XX_1_XXGi#${k8s_new_size}Gi#g" $k8s_target_pvc-pvc.yaml
sed -i "s#pvc-rsync-copier#${k8s_source_pvc}#g" $k8s_target_pvc-pvc.yaml
sed -i "s#XXX_NAMESPACE_XXX#${k8s_namespace}#g" $k8s_target_pvc-pvc.yaml

cp ../../../templates/rsync.yaml $k8s_target_pvc-rsync.yaml
sed -i "s#XXX_SOURCE_PVC_XXX#${k8s_target_pvc}#g" $k8s_target_pvc-rsync.yaml
sed -i "s#XXX_TARGET_PVC_XXX#${k8s_source_pvc}#g" $k8s_target_pvc-rsync.yaml
sed -i "s/pvc-rsync-copier-deployment-name/rsync-${k8s_target_pvc}/g" $k8s_target_pvc-rsync.yaml

echo "INFO: Phase1: manifests created in workdir:" `pwd`
ls -l $k8s_target_pvc-pvc.yaml
ls -l $k8s_target_pvc-rsync.yaml

echo 
echo "# Steps to perform:" | tee $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace create -f $workdir/phase1/$k8s_target_pvc-pvc.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace create -f $workdir/phase1/$k8s_target_pvc-rsync.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace rollout status deployment rsync-$k8s_target_pvc" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "#### Wait for rsync to complete" >> $workdir/$k8s_target_pvc-script.sh
echo "while true" >> $workdir/$k8s_target_pvc-script.sh
echo "do" >> $workdir/$k8s_target_pvc-script.sh
echo "sleep 10" >> $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace logs deployment/rsync-$k8s_target_pvc | grep Done\ with\ rsync" >> $workdir/$k8s_target_pvc-script.sh
echo "if [ \$? ]; then" >>  $workdir/$k8s_target_pvc-script.sh
echo "  echo Rsync completed...." >>  $workdir/$k8s_target_pvc-script.sh
echo "  kubectl --insecure-skip-tls-verify -n $k8s_namespace logs deployment/rsync-$k8s_target_pvc | tail -n 10" >> $workdir/$k8s_target_pvc-script.sh
echo "  break" >>  $workdir/$k8s_target_pvc-script.sh
echo "fi" >>  $workdir/$k8s_target_pvc-script.sh
echo "done" >> $workdir/$k8s_target_pvc-script.sh
echo "echo Double check whether rsync is completed from POD logs before deletion...." >>  $workdir/$k8s_target_pvc-script.sh
echo "while true" >>  $workdir/$k8s_target_pvc-script.sh
echo "  do" >>  $workdir/$k8s_target_pvc-script.sh
echo "  echo \"Enter (yes/no)?\" " >>  $workdir/$k8s_target_pvc-script.sh
echo "  read choice " >>  $workdir/$k8s_target_pvc-script.sh
echo "  if [ \$choice == \"yes\" ]; then " >>  $workdir/$k8s_target_pvc-script.sh
echo "    break"  >>  $workdir/$k8s_target_pvc-script.sh
echo "  fi"  >>  $workdir/$k8s_target_pvc-script.sh
echo "done"  >>  $workdir/$k8s_target_pvc-script.sh

echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace delete -f $workdir/phase1/$k8s_target_pvc-rsync.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace delete pvc $k8s_source_pvc" | tee -a $workdir/$k8s_target_pvc-script.sh

echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace create -f $workdir/phase2/$k8s_target_pvc-pvc.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace create -f $workdir/phase2/$k8s_target_pvc-rsync.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace rollout status deployment rsync-$k8s_target_pvc" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "#### Wait for rsync to complete" | tee -a $workdir/$k8s_target_pvc-script.sh

echo "while true" >> $workdir/$k8s_target_pvc-script.sh
echo "do" >> $workdir/$k8s_target_pvc-script.sh
echo "sleep 10" >> $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace logs deployment/rsync-$k8s_target_pvc | grep Done\ with\ rsync" >> $workdir/$k8s_target_pvc-script.sh
echo "if [ \$? ]; then" >>  $workdir/$k8s_target_pvc-script.sh
echo "  echo Rsync completed...." >>  $workdir/$k8s_target_pvc-script.sh
echo "  kubectl --insecure-skip-tls-verify -n $k8s_namespace logs deployment/rsync-$k8s_target_pvc | tail -n 10" >> $workdir/$k8s_target_pvc-script.sh
echo "  break" >>  $workdir/$k8s_target_pvc-script.sh
echo "fi" >>  $workdir/$k8s_target_pvc-script.sh
echo "done" >> $workdir/$k8s_target_pvc-script.sh
echo "echo Double check whether rsync is completed from POD logs before deletion...." >>  $workdir/$k8s_target_pvc-script.sh
echo "while true" >>  $workdir/$k8s_target_pvc-script.sh
echo "  do" >>  $workdir/$k8s_target_pvc-script.sh
echo "  echo \"Enter (yes/no)?\" " >>  $workdir/$k8s_target_pvc-script.sh
echo "  read choice " >>  $workdir/$k8s_target_pvc-script.sh
echo "  if [ \$choice == \"yes\" ]; then " >>  $workdir/$k8s_target_pvc-script.sh
echo "    break"  >>  $workdir/$k8s_target_pvc-script.sh
echo "  fi"  >>  $workdir/$k8s_target_pvc-script.sh
echo "done"  >>  $workdir/$k8s_target_pvc-script.sh


echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace delete -f $workdir/phase2/$k8s_target_pvc-rsync.yaml" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "kubectl --insecure-skip-tls-verify -n $k8s_namespace delete pvc $k8s_target_pvc" | tee -a $workdir/$k8s_target_pvc-script.sh
echo "Script created at: $workdir/$k8s_target_pvc-script.sh"
