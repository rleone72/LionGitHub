#!/bin/bash
cpepod=`oc get pods | grep cpe | awk '{print $1}'`
oc rsh $cpepod
mkdir -p configDropins/overrides/SUFAS/SUFAS/
exit
