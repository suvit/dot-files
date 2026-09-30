#!/bin/bash
set -Eeuxo pipefail

HOST=192.168.1.146
PROJECT_USER=copy-mrp-11

# Stop service and remove config
ssh "root@${HOST}" "service odoo-${PROJECT_USER} stop; rm /etc/systemd/system/${PROJECT_USER}.service"
# Drop user
ssh "root@${HOST}" "deluser ${PROJECT_USER}; rm -r /home/${PROJECT_USER}"
# Drop nginx
ssh "root@${HOST}" "rm /etc/nginx/sites-enabled/ansible-${PROJECT_USER}.conf; service nginx reload;"

# Drop db


