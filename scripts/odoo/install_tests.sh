#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")

export PGHOST=localhost
export PGPORT=65432

STAND=11_mrp
INSTALL=${STAND}_install
TEMPLATE=${STAND}_template
DB=${STAND}_test

INSTALL_MODULE=format_mrp_menu
INIT_MODULE=_test_format_core
TEST_MODULE=_test_format_mrp,_test_format_crm
MODE=${1:-'install,template,test'}

if grep -q "install" <<< "$MODE"; then
  dropdb --if-exists ${INSTALL}
  $script_dir/run_test.sh -d ${INSTALL} -i ${INSTALL_MODULE}
fi

if grep -q "template" <<< "$MODE"; then
  dropdb --if-exists ${TEMPLATE}
  createdb -O $USER -T ${INSTALL} ${TEMPLATE}
  $script_dir/run_test.sh -d ${TEMPLATE} -i ${INIT_MODULE}
fi

if grep -q "test" <<< "$MODE"; then
  dropdb --if-exists ${DB}
  createdb -O $USER -T ${TEMPLATE} ${DB}
  $script_dir/run_test.sh -d ${DB} -i ${TEST_MODULE}
fi
