#!/bin/bash

DIR=$(mktemp -d)
NAMESPACE=$(oc project -q)

cluster="$(kubectl get icp4acluster)"

if [[ !  "No resources found" =~ $cluster ]]; then

  echo "Gathering the custom resource yaml file used by the operator to setup the environment"
  kubectl get icp4acluster -o yaml > $DIR/config.yaml

  echo "Gathering the OCP version"
  kubectl version > $DIR/version.txt

  echo "Gathering information about the nodes"
  kubectl get nodes -o wide > $DIR/nodes.txt

  echo "Gathering information about the pod status"
  kubectl get pods > $DIR/pods.txt

  echo "Gathering information about the pod containers"
  kubectl get pods -o jsonpath="{..image}" > $DIR/containerInfo.txt

  echo "Gathering route configuration" 
  kubectl get route > $DIR/routes.txt

  echo "Gathering the defined secrets" 
  kubectl get secrets > $DIR/secrets.txt

  echo "Gathering the persistent volumes"
  kubectl get pv > $DIR/pv.txt

  echo "Gathering the persistent volume claims"
  kubectl get pvc > $DIR/pvc.txt

  echo "Gathering network security policies"
  kubectl get netpol > $DIR/netpol.txt

  echo "Gathering the operator log"
  pod="$(kubectl get pods -o name | grep ibm-cp4a-operator  | awk -F "/" '{print $2}')"
  kubectl logs $pod > $DIR/$pod.log

  #Collecting the description, configuration, logs and referenced secrets of UMS pods
  pods="$(kubectl get pod --selector='app.kubernetes.io/component=UMS' -o custom-columns=NAME:.metadata.name --no-headers)"

  for pod in $pods
    do
      echo "Gathering description, configuration and log for $pod"
      kubectl describe pod $pod > $DIR/$pod-description.txt	
      kubectl get pod $pod -o yaml > $DIR/$pod-configuration.txt	
      echo "Secrets referenced in $pod:" >> $DIR/referencedSecrets.txt
      kubectl get pods $pod -o json |grep secretName >> $DIR/referencedSecrets.txt
      mkdir $DIR/$pod-logs
      oc cp $pod:/logs/UMS/$pod/  $DIR/$pod-logs
    done

  echo "Zip the must-gather directory"
  outputdir=$(pwd)
  (cd $DIR; zip -r $outputdir/ums-must-gather-$(date +"%y-%m-%d_%T").zip ./*)
  rm -rf $DIR

  echo "Done! Provide the $DIR.zip file to the IBM support."

else
   echo "Change to the project where you deployed CP4BA, then re-run the script"
fi
