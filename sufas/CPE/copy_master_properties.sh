#!/bin/bash
cpepod=`oc get pods | grep cpe | awk '{print $1}'`
echo Copying master.properties to pod $cpepod
oc cp master.properties $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/configDropins/overrides/SUFAS/SUFAS/
