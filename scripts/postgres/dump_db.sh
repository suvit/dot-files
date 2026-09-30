#!/bin/bash
set -Eeuxo pipefail

# export PGHOST=localhost
# export PGPORT=16432

# Создаем функцию-обертку, которая подменяет pg_dump
pg_dump() {
    docker exec -t \
           postgresdb16 pg_dump -U vik "$@"
}

# $1 - db
# $2 - store_name

DATE=`date '+%Y-%m-%d'`
DB=$1
DUMP_NAME=${2:-suvit_dump_pgsql_$1_${DATE}.gz}

pg_dump -OC ${DB} | gzip -c > ${DUMP_NAME} 2>/dev/null