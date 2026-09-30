#!/bin/bash
set -Eeuxo pipefail

SHOST='192.168.1.146'
DHOST='192.168.1.153'
PROJECT_USER=mrp-11

# db
# ssh "root@${SHOST}" "service odoo-${PROJECT_USER} stop"
# time ssh "root@${SHOST}" "sudo -u postgres pg_dump -OC 11_mrp | gzip -c > /home/mrp-11/.local/share/Odoo/db_11_mrp.gz 2>/dev/null"
# time scp -3 "root@${SHOST}:/home/mrp-11/.local/share/Odoo/db_11_mrp.gz" "root@${DHOST}:/home/mrp-11/.local/share/Odoo"
# ssh "root@${DHOST}" "service odoo-${PROJECT_USER} stop"
# ssh "root@${DHOST}" "sudo -u postgres dropdb --if-exists 11_mrp; sudo -u postgres createdb -O ${PROJECT_USER} 11_mrp;"
# time ssh "root@${DHOST}" "cd /home/mrp-11/.local/share/Odoo/; gunzip -c db_11_mrp.gz | sudo -u postgres psql -d 11_mrp > /dev/null"

# files
# time ssh "root@${SHOST}" "cd /home/mrp-11/.local/share/Odoo; tar -zcf mrp_11_filestore.tar.gz filestore/ sessions/"
time scp -3 "root@${SHOST}:/home/mrp-11/.local/share/Odoo/mrp_11_filestore.tar.gz" "root@${DHOST}:/home/mrp-11/.local/share/Odoo"
time ssh "root@${DHOST}" "cd /home/mrp-11/.local/share/Odoo; rm -r filestore/ sessions/; tar -zxf mrp_11_filestore.tar.gz"
ssh "root@${DHOST}" "service odoo-${PROJECT_USER} start"