# echo ${BASH_SOURCE}
script_dir=$(dirname "$BASH_SOURCE")
$script_dir/run_pg.sh
$script_dir/run_cryptdisk.sh
$script_dir/run_pk.sh
