#!/bin/bash
# Add LDAP Bind user and passwort to the "ldap-bind-secret"
oc create secret generic ldap-bind-secret \
       	--from-literal=ldapUsername="CN=S00290,OU=EFD-BIT-EASY-Server,OU=Server,OU=BIT,OU=LESD,DC=sszadmbit,DC=sszad,DC=admin,DC=ch" \
	--from-literal=ldapPassword="IXF5Y19AaRo5" \
       	--from-literal=ldapdb00048aUsername="CN=S00290,OU=EFD-BIT-EASY-Server,OU=Server,OU=BIT,OU=LESD,DC=sszadmbit,DC=sszad,DC=admin,DC=ch" \
	--from-literal=ldapdb00048aPassword="IXF5Y19AaRo5" \
       	--from-literal=ldapdb00050aUsername="CN=S00290,OU=EFD-BIT-EASY-Server,OU=Server,OU=BIT,OU=LESD,DC=sszadmbit,DC=sszad,DC=admin,DC=ch" \
	--from-literal=ldapdb00050aPassword="IXF5Y19AaRo5" \
       	--from-literal=ldapdb00051aUsername="CN=S00290,OU=EFD-BIT-EASY-Server,OU=Server,OU=BIT,OU=LESD,DC=sszadmbit,DC=sszad,DC=admin,DC=ch" \
	--from-literal=ldapdb00051aPassword="IXF5Y19AaRo5" \
       	--from-literal=ldapldsUsername="CN=eIAM-ESTV-EASY-BindUser,CN=Users,CN=Admin,CN=eiam,DC=lds,DC=eiam-a,DC=admin,DC=ch" \
	--from-literal=ldapldsPassword="(c}Enf%mvVt6"
