kubectl create secret generic ibm-fncm-secret --from-literal=gcdDBUsername="M_SSO_FNGCD" --from-literal=gcdDBPassword="gdDDyzK69SDA2AYnS5Mm" \
--from-literal=docsDBUsername="M_SSO_FNOS04" --from-literal=docsDBPassword="gdDDyzK69SDA2AYnS5Mm" \
--from-literal=dosDBUsername="M_SSO_FNOS01" --from-literal=dosDBPassword="gdDDyzK69SDA2AYnS5Mm" \
--from-literal=tosDBUsername="M_SSO_FNOS02" --from-literal=tosDBPassword="gdDDyzK69SDA2AYnS5Mm" \
--from-literal=aeosDBUsername="M_SSO_FNOS03" --from-literal=aeosDBPassword="gdDDyzK69SDA2AYnS5Mm" \
--from-literal=appLoginUsername="S00286" --from-literal=appLoginPassword="jpq9XVTRQHSR" \
--from-literal=keystorePassword="passw0rd" \
--from-literal=ltpaPassword="passw0rd"
