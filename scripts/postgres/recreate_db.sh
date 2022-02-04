#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=65432
DATE=${1:-`date '+%Y-%m-%d'`}
DB=$2
DB_FULL=${3:-suvit_dump_pgsql_${DB}_11.0_$DATE.gz}

dropdb --if-exists ${DB}
createdb -O $USER ${DB}
# TODO var date
# gunzip -c ${DB_FULL} | ./pgdump_10_to_9.py | psql -d ${DB} > /dev/null
gunzip -c ${DB_FULL} | nice psql -d ${DB} > /dev/null
psql -d ${DB} -c "delete from ir_mail_server where name != 'localhost';"
psql -d ${DB} -c "delete from ir_config_parameter where key LIKE 'SENTRY%';"
psql -d ${DB} -c "update ir_cron set active = False"
# TODO drop history models
