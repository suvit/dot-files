#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=65432

DB=14_mrp

pg_dump -OC ${DB} | gzip -c > ${DB}_dev_$( date +%F ).gz 2>/dev/null
