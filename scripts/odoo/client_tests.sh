#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")

export PGHOST=localhost
export PGPORT=65432

STAND=${ODOO_VERSION:-11}_baltika
INSTALL=${STAND}_install
TEMPLATE=${STAND}_template
DB=${STAND}_test

INSTALL_MODULE=format_heineken
INIT_MODULE=_test_format_heineken
TEST_MODULE=_test_format_baltika
MODE=${1:-'install,template,test'}

if grep -q "install" <<< "$MODE"; then
  dropdb --if-exists ${INSTALL}
  $script_dir/run_test.sh -d ${INSTALL} -i ${INSTALL_MODULE} ${@: 2}
fi

if grep -q "template" <<< "$MODE"; then
  dropdb --if-exists ${TEMPLATE}
  createdb -O $USER -T ${INSTALL} ${TEMPLATE}
  $script_dir/run_test.sh -d ${TEMPLATE} -i ${INIT_MODULE} ${@: 2}
fi

if grep -q "test" <<< "$MODE"; then
  dropdb --if-exists ${DB}
  createdb -O $USER -T ${TEMPLATE} ${DB}
  $script_dir/run_test.sh -d ${DB} -i ${TEST_MODULE} ${@: 2}
fi
