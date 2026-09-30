#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")
# Запускать

export PGHOST=localhost
export PGPORT=65432

OU_ROOT=/opt/suvit/odoo/OpenUpgrade
DB=mrp
TARGET_VERSION=19.0

function migrate {
    old_ver=$1
    new_ver=$2

    dropdb --if-exists ${new_ver}_${DB}
    # createdb -O $USER -T ${old_ver}_${DB} ${new_ver}_${DB}
    psql -tAc "SELECT 1 FROM pg_database WHERE datname='${new_ver}_${DB}'" | grep -q 1 || createdb -O $USER -T ${old_ver}_${DB} ${new_ver}_${DB}

    MIG_ROOT=$OU_ROOT/${DB}-${old_ver}-${new_ver}
    cd $MIG_ROOT

    # export OPENUPGRADE_TARGET_VERSION=${TARGET_VERSION}
    ~/dotfiles/scripts/odoo/run_odoo.sh -d ${new_ver}_${DB} -u all --stop-after-init > $MIG_ROOT/migration.log 2> $MIG_ROOT/error.log
}
# Исходная база 11_mrp, мигрируем ее в 14_mrp
migrate 11 12
migrate 12 13
migrate 13 14
migrate 14 15
migrate 15 16
migrate 16 17
migrate 17 18
migrate 18 19
