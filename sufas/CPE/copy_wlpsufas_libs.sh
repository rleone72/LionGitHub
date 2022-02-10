#!/bin/bash
cpepod=`oc get pods | grep cpe | awk '{print $1}'`
echo Copying jersey-bundle-1.19.jar to pod $cpepod
oc cp sufaslibs/jackson-core-asl-1.9.13.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jackson-core-asl-1.9.13.jar
oc cp sufaslibs/jackson-jaxrs-1.9.13.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jackson-jaxrs-1.9.13.jar
oc cp sufaslibs/jackson-mapper-asl-1.9.13.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jackson-mapper-asl-1.9.13.jar
oc cp sufaslibs/jackson-xc-1.9.13.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jackson-xc-1.9.13.jar
oc cp sufaslibs/jakarta.activation-1.2.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jakarta.activation-1.2.1.jar
oc cp sufaslibs/jakarta.annotation-api-1.3.5.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jakarta.annotation-api-1.3.5.jar
oc cp sufaslibs/jakarta.inject-2.6.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jakarta.inject-2.6.1.jar
oc cp sufaslibs/jakarta.ws.rs-api-2.1.6.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jakarta.ws.rs-api-2.1.6.jar
oc cp sufaslibs/jdom-1.1.3.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jdom-1.1.3.jar
oc cp sufaslibs/jersey-common-2.29.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jersey-common-2.29.1.jar
oc cp sufaslibs/jersey-container-servlet-core-2.29.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jersey-container-servlet-core-2.29.1.jar
oc cp sufaslibs/jersey-json-1.19.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jersey-json-1.19.jar
oc cp sufaslibs/jersey-media-json-jackson-2.29.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jersey-media-json-jackson-2.29.1.jar
oc cp sufaslibs/jettison-1.4.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jettison-1.4.1.jar
oc cp sufaslibs/jsr311-api-1.1.1.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/jsr311-api-1.1.1.jar
oc cp sufaslibs/osgi-resource-locator-1.0.3.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/osgi-resource-locator-1.0.3.jar
oc cp sufaslibs/rome-0.9.jar $cpepod:/opt/ibm/wlp/usr/servers/defaultServer/lib/bootstrap/rome-0.9.jar
