#!/bin/bash 

drive=/run/media/peddycoartte/Development/Data/
echo "Drive: ${drive}"

sudo chown -R $(id -u):$(id -g) "${drive}" \
&& sudo find ${drive}" -type d -exec chmod 755 {} \; \
&& sudo find ${drive}" -type f -exec chmod 644 {} \;
