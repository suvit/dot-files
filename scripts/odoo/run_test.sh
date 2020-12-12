script_dir=$(dirname "$BASH_SOURCE")
GITLAB_CI=1 $script_dir/run_odoo.sh $@ --xmlrpc-port 8999 --stop-after-init
