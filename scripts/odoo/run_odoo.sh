#!/bin/bash
set -Eeuxo pipefail

pipenv run odoo $@ -c local.conf
