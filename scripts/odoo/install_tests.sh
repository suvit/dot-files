#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=65432
STAND=baltika
TEMPLATE=${STAND}_template
DB=${STAND}_test
INIT_MODULE=format_heineken
TEST_MODULE=_test_format_heineken

# dropdb --if-exists ${TEMPLATE}
# ./run_test.sh -d ${TEMPLATE} -i ${INIT_MODULE}

dropdb --if-exists ${DB}
createdb -O odoo11 -T ${TEMPLATE} ${DB}
./run_test.sh -d ${DB} -i ${TEST_MODULE}
