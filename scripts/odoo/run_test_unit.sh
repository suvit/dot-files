#!/bin/bash
set -Eeuxo pipefail

script_dir=$(dirname "$BASH_SOURCE")
$script_dir/run_test.sh $@ --test-enable