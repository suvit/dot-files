#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=65432
DATE=${1:-`date '+%Y-%m-%d'`}

dropdb --if-exists 11_mrp
createdb -O $USER 11_mrp
# TODO var date
# gunzip -c suvit_dump_pgsql_11_mrp_11.0_${DATE}.gz | ./pgdump_10_to_9.py | psql -d 11_mrp > /dev/null
gunzip -c suvit_dump_pgsql_11_mrp_11.0_${DATE}.gz | nice psql -d 11_mrp > /dev/null
psql -d 11_mrp -c "delete from ir_mail_server where name != 'localhost';"
psql -d 11_mrp -c "delete from ir_config_parameter where key LIKE 'SENTRY%';"
psql -d 11_mrp -c "update ir_cron set active = False"
# TODO drop history models
