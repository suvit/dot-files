function ssh_alias() {
    ssh $@;
    setterm -default -clear all;
}

alias ssh=ssh_alias

# Claude Code: подключение личных настроек
alias claude='claude --settings ~/dotfiles/claude/settings.json'
