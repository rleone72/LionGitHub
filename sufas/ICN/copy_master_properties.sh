#!/bin/bash
icnpod=`oc get pods | grep navi | awk '{print $1}'`
echo Copying master.properties to pod $icnpod
oc cp master.properties $icnpod:/opt/ibm/wlp/usr/servers/defaultServer/configDropins/overrides/SUFAS/SUFAS/
