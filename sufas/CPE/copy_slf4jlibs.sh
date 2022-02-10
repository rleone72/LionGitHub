#!/bin/bash
cpepod=`oc -n ssotest get pods | grep cpe | awk '{print $1}'`
echo Copying slf library to pod $cpepod on namespace ssotest
oc -n ssotest cp slf4j-api-1.7.25.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/slf4j-api-1.7.25.jar
