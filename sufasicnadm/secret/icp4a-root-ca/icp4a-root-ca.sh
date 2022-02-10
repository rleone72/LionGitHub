#!/bin/bash
# Add BIT root CA certificate for the "ldap-ssl-secret"
kubectl create secret generic icp4a-root-ca --from-file=tls.crt=./icp4a-root-ca.pem
