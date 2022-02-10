#!/bin/bash
# Add BIT root CA certificate for the "ldap-ssl-secret"
kubectl create secret generic ldap-ssl-secret --from-file=tls.crt=./ldap_db00048a.pem
