#!/bin/bash
# Add BIT root CA certificate for the "ldap-ssl-secret"
kubectl create secret generic ldap-ssl-secret --from-file=tls.crt=/home/cp4ba-inst/certs/swissgovernment-e-root01.pem
# sleep 5
kubectl create secret generic ldap-intra-ssl-secret --from-file=tls.crt=/home/cp4ba-inst/certs/swissgovernment-e-intra01.pem
timeout 5
exit N
