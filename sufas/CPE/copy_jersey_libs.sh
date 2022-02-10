#!/bin/bash
cpepod=`oc get pods | grep cpe | awk '{print $1}'`
echo Copying jersey-bundle-1.19.jar to pod $cpepod
oc cp jersey-bundle-1.19.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jersey-bundle-1.19.jar
