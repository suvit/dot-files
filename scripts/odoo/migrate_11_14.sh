#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")
# Запускать

export PGHOST=localhost
export PGPORT=65432

OU_ROOT=/opt/suvit/odoo/OpenUpgrade

function migrate {
    old_ver=$1
    new_ver=$2

    dropdb --if-exists ${new_ver}_mrp
    createdb -O $USER -T ${old_ver}_mrp ${new_ver}_mrp

    MIG_ROOT=$OU_ROOT/mrp-${old_ver}-${new_ver}
    cd $MIG_ROOT

    # export OPENUPGRADE_TARGET_VERSION=14.0
    ~/dotfiles/scripts/odoo/run_odoo.sh -d ${new_ver}_mrp -u all --stop-after-init # > $MIG_ROOT/migration.log 2> $MIG_ROOT/error.log
}
# Исходная база 11_mrp, мигрируем ее в 14_mrp
migrate 11 12
migrate 12 13
migrate 13 14
