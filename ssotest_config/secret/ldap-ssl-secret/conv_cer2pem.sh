#!/bin/bash
# Convert certificate CER to PEM format
openssl x509 -inform DER -in /home/cp4ba-inst/certs/swissgovernment-e-root01.cer -outform PEM -out /home/cp4ba-inst/certs/swissgovernment-e-root01.pem
sleep 2
openssl x509 -inform DER -in /home/cp4ba-inst/certs/swissgovernment-e-intra01.cer -outform PEM -out /home/cp4ba-inst/certs/swissgovernment-e-intra01.pem
timeout 5
exit N
