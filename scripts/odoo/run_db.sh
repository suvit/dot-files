#!/bin/bash
set -Eeuxo pipefail

export PGHOST=localhost
export PGPORT=16432

psql $@