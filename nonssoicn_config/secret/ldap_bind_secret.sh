#!/bin/bash
# Add LDAP Bind user and passwort to the "ldap-bind-secret"
oc create secret generic ldap-bind-secret \
       	--from-literal=ldapUsername="CN=S00290,OU=EFD-BIT-EASY-Server,OU=Server,OU=BIT,OU=LESD,DC=sszadmbit,DC=sszad,DC=admin,DC=ch" \
	--from-literal=ldapPassword="IXF5Y19AaRo5"
