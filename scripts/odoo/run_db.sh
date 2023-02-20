#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=65432

psql $@