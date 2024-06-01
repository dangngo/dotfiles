#!/bin/sh
export ZDOTDIR=$HOME/.config/zsh

# General
setopt autocd
setopt extendedglob
setopt nomatch
setopt notify
# setopt menucomplete
unsetopt menucomplete
setopt automenu
setopt interactive_comments
unsetopt BEEP

# Disable ctrl-s to freeze terminal.
stty stop undef
# Disable highlight pasted content
zle_highlight=('paste:none')

# History
HISTFILE=~/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt appendhistory
setopt sharehistory
setopt incappendhistory

# Colors
autoload -Uz colors && colors


# Completions
zstyle ':completion:*' menu select
zstyle ':completion::complete:lsof:*' menu yes select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # case insensitive
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} # set list-colors to enable filename colorizing
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'exa -1 --color=always $realpath' # preview directory's content with exa when completing cd
zmodload zsh/complist

# _comp_options+=(globdots) # Include hidden files.

# Source functions
source "$ZDOTDIR/functions"

# Enable vim mode
_zsh_add_file "vim-mode"

# Keybindings
_zsh_add_file "keybindings"

# Set aliases
_add_file "$HOME/.aliases"

# Plugins
_zsh_add_file "plugins"

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND="fd . $HOME --hidden"
export FZF_DEFAULT_OPTS="--layout=reverse --inline-info --height=30%"

# ASDF
[ -f "/opt/homebrew/opt/asdf/libexec/asdf.sh" ] && . /opt/homebrew/opt/asdf/libexec/asdf.sh
# [ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"

# misc (binary manager)
[ -f "$HOME/.local/bin/mise" ] && eval "$($HOME/.local/bin/mise activate zsh)"
[ -f "$HOME/.local/bin/mise" ] && eval "$($HOME/.local/bin/mise hook-env)"

# Kubectl
source <(kubectl completion zsh)

# Prompt
[ -x "$(command -v starship)" ] && eval "$(starship init zsh)"

# Z
[ -x "$(command -v zoxide)" ] && eval "$(zoxide init zsh)"
