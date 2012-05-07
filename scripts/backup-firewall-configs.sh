#!/bin/bash

for i in fw1 fw2; do

lua fsbash.lua << EOT
cd firewalls/$i
lmount /etc
fs
#cp to local config storage
tar -czf /var/backup/$i/etc-$i-$(date +"%Y-%m-%d").tgz etc
cd
lumount /home/mischa/.fsba/sshfs/firewalls/$i/etc
exit
EOT

done

