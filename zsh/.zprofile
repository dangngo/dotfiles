#!/bin/sh

#umask 022
export EDITOR="nvim"
export TERMINAL="wezterm"
export NVM_DIR="$HOME/.nvm"

export DISABLE_AUTO_TITLE='true'

# Bat as man pages reader
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# Disable AWS pager
export AWS_PAGER=""

PATH="$HOME/.local/bin:$PATH"
PATH="/opt/homebrew/bin:$PATH"

# Homebrew completions
#FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"

# set PATH so it includes user's private bin if it exists
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"

# Go binary
[ -d "$HOME/go/bin" ] && PATH="$HOME/go/bin:$PATH"

# Adds `~/.scripts` and all subdirectories to $PATH
[ -d "$HOME/.scripts" ] && PATH="$PATH:$(du "$HOME/.scripts/" | cut -f2 | tr '\n' ':' | sed 's/:*$//')"

# if [ -d "$HOME/.work/functions" ]; then
#   for file in "$HOME/.work/functions"/*; do
#     . $file
#   done
# fi

PATH="/usr/local/bin:$PATH"
export PATH
