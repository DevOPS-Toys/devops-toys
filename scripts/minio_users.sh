#!/bin/bash

USERNAME=$1
PASSWORD=$2

cat <<EOF >./temp_user_config.txt
username=${USERNAME}
password=${PASSWORD}
disabled=false
policies=readwrite,consoleAdmin,diagnostics
setPolicies=false
EOF

kubectl --namespace minio create secret generic centralized-minio-users \
--from-file=username1=./temp_user_config.txt \
--output json \
--dry-run=client | kubeseal --format yaml \
--controller-name=sealed-secrets \
--controller-namespace=sealed-secrets | tee ./manifesta/dev/minio/secret-minio-users.yaml > /dev/null

rm -f ./temp_user_config.txt
