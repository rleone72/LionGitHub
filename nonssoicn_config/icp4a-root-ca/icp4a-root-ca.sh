#!/bin/bash
# Add BIT root CA certificate for the "ldap-ssl-secret"
kubectl create secret generic icp4a-root-ca --from-file=tls.crt=/home/cp4ba-inst/nonssoicn_config/icp4a-root-ca/icp4a-root-ca.pem
