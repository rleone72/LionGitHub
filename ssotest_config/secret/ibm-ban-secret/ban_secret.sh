kubectl create secret generic ibm-ban-secret \
 --from-literal=navigatorDBUsername="M_SSO_ICNCFG01" \
 --from-literal=navigatorDBPassword="gdDDyzK69SDA2AYnS5Mm" \
 --from-literal=keystorePassword="passw0rd" \
 --from-literal=ltpaPassword="passw0rd" \
 --from-literal=appLoginUsername="S00286" \
 --from-literal=appLoginPassword="jpq9XVTRQHSR" \
 --from-literal=jMailUsername="mailadmin" \
 --from-literal=jMailPassword="{xor}GDoxNiosbg=="
