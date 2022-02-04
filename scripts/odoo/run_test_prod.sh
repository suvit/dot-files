#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")
PROD_CALC=1 $script_dir/run_test.sh $@ --test-enable
