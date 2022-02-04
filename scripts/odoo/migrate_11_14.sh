#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")
# Запускать

export PGHOST=localhost
export PGPORT=65432

# Исходная база 11_mrp, мигрируем ее в 14_mrp

# 11 -> 12
dropdb --if-exists 12_mrp
createdb -O $USER -T 11_mrp 12_mrp

OU_ROOT = /opt/odoo/OpenUpgrade/
cd $OU_ROOT/mrp-11-12
~/dotfiles/scripts/odoo/run_odoo.sh -d 12_mrp -u all --stop-after-init

exit 0

dropdb --if-exists 13_mrp
createdb -O $USER -T 12_mrp 13_mrp

cd $OU_ROOT/mrp-12-13
~/dotfiles/scripts/odoo/run_odoo.sh -d 13_mrp -u all --stop-after-init
