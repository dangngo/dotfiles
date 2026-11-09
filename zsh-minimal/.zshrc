# Minimal zsh config: a single file, no plugins, nothing to download.
# For airgapped machines. Mimics the full `zsh` package using only zsh built-ins:
#   zcomet/fzf-tab -> menu completion, starship -> native prompt, zoxide -> cdr + `z`,
#   fzf history -> incremental pattern search, zsh-syntax-highlighting -> command highlighter.
#
# Usage: copy to ~/.zshrc (or `stow zsh-minimal` instead of `stow zsh`)

####################
# Environment
####################
typeset -U path # dedupe PATH entries
for dir in /usr/local/bin "$HOME/.cargo/bin" "$HOME/go/bin" "$HOME/.local/bin"; do
  [[ -d $dir ]] && path=("$dir" $path)
done
export PATH

if (( $+commands[nvim] )); then export EDITOR=nvim
elif (( $+commands[vim] )); then export EDITOR=vim
else export EDITOR=vi
fi
export VISUAL=$EDITOR
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
export AWS_PAGER=""
(( $+commands[bat] )) && export MANPAGER="sh -c 'col -bx | bat -l man -p'"

ZCACHE=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
[[ -d $ZCACHE ]] || mkdir -p "$ZCACHE"

####################
# General options
####################
setopt autocd extendedglob nomatch notify interactive_comments
setopt automenu
unsetopt menucomplete beep
stty stop undef 2>/dev/null # disable ctrl-s freezing the terminal
zle_highlight=('paste:none')

####################
# History
####################
HISTFILE=$HOME/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt hist_find_no_dups hist_ignore_all_dups hist_ignore_space
setopt appendhistory sharehistory incappendhistory

####################
# Completion
####################
(( $+commands[dircolors] )) && eval "$(dircolors -b)"
zmodload zsh/complist
autoload -Uz compinit
compinit -d "$ZCACHE/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # case insensitive
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$ZCACHE/compcache"
zstyle ':completion::complete:lsof:*' menu yes select

(( $+commands[kubectl] )) && source <(kubectl completion zsh)
(( $+commands[helm] )) && source <(helm completion zsh)

####################
# Vim mode
####################
bindkey -v
export KEYTIMEOUT=1

bindkey -M menuselect '^h' vi-backward-char
bindkey -M menuselect '^k' vi-up-line-or-history
bindkey -M menuselect '^l' vi-forward-char
bindkey -M menuselect '^j' vi-down-line-or-history
bindkey -M menuselect '^[[Z' vi-up-line-or-history
bindkey -v '^?' backward-delete-char

# Cursor shape and prompt character follow the vi mode
function zle-keymap-select {
  case $KEYMAP in
    vicmd) echo -ne '\e[2 q' ;; # block
    viins|main) echo -ne '\e[6 q' ;; # beam
  esac
  [[ $KEYMAP == vicmd ]] && _prompt_symbol='❮' || _prompt_symbol='❯'
  zle reset-prompt
}
zle -N zle-keymap-select
function zle-line-init {
  zle -K viins
  _prompt_symbol='❯'
  echo -ne '\e[6 q'
}
zle -N zle-line-init

####################
# Keybindings
####################
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search edit-command-line
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
zle -N edit-command-line

bindkey '^p' up-line-or-beginning-search
bindkey '^n' down-line-or-beginning-search
bindkey -r '^u'
bindkey -r '^d'
bindkey '^e' edit-command-line
bindkey -M vicmd '^e' edit-command-line
bindkey '^r' history-incremental-pattern-search-backward # replaces fzf history
bindkey -M vicmd '^r' history-incremental-pattern-search-backward
bindkey -M isearch '^p' history-incremental-pattern-search-backward
bindkey -M isearch '^n' history-incremental-pattern-search-forward

####################
# Command highlighting (replaces zsh-syntax-highlighting)
####################
# Colors the command word green when it exists and red when it doesn't
function _highlight_command {
  region_highlight=(${region_highlight:#*memo=cmdhl})
  [[ $BUFFER =~ '^[[:space:]]*([^[:space:]]+)' ]] || return
  local word=$match[1] start=$(( mbegin[1] - 1 )) end=$mend[1] style
  if (( $+commands[$word] || $+functions[$word] || $+aliases[$word] || $+builtins[$word] )) \
    || [[ -n $reswords[(r)$word] || -x $word ]]; then
    style=fg=green
  else
    style=fg=red
  fi
  region_highlight+=("$start $end $style memo=cmdhl")
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw _highlight_command

####################
# Directory jumping (replaces zoxide)
####################
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs
zstyle ':chpwd:*' recent-dirs-file "$ZCACHE/recent-dirs"
zstyle ':chpwd:*' recent-dirs-max 500
zstyle ':chpwd:*' recent-dirs-default true

# z <words...>: cd to the most recent directory matching all words in order (case insensitive)
function z {
  (( $# )) || { cd ~; return }
  [[ $# -eq 1 && -d $1 ]] && { cd -- "$1"; return }
  local pattern="(#i)*${(j:*:)@}*" entry dir
  for entry in ${(f)"$(cdr -l 2>/dev/null)"}; do
    dir=${${entry##<->[[:space:]]##}/#\~/$HOME}
    if [[ ${dir:t} == $~pattern || $dir == $~pattern ]] && [[ -d $dir ]]; then
      cd -- "$dir"
      return
    fi
  done
  print -u2 "z: no recent directory matches '$*'"
  return 1
}

####################
# Prompt (replaces starship)
####################
setopt prompt_subst
_git_info=''
_kube_info=''
_kube_mtime=''

# Branch, ahead/behind and file status from a single `git status` call
function _prompt_git {
  _git_info=''
  local line branch ahead=0 behind=0 staged=0 modified=0 untracked=0 conflicted=0
  local -a lines
  lines=(${(f)"$(git status --porcelain=v2 --branch 2>/dev/null)"}) || return
  (( $#lines )) || return
  for line in $lines; do
    case $line in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.ab '*) ahead=${${(s: :)line}[3]#+}; behind=${${(s: :)line}[4]#-} ;;
      'u '*) (( conflicted++ )) ;;
      '? '*) (( untracked++ )) ;;
      [12]' '*)
        [[ ${line[3]} != . ]] && (( staged++ ))
        [[ ${line[4]} != . ]] && (( modified++ ))
        ;;
    esac
  done
  [[ -n $branch ]] || return
  [[ $branch == '(detached)' ]] && branch=${${(M)lines:#\# branch.oid *}#\# branch.oid }[1,7]
  local flags=''
  (( conflicted )) && flags+='='
  (( ahead && behind )) && flags+='⇕' || { (( ahead )) && flags+='⇡'; (( behind )) && flags+='⇣'; }
  (( staged )) && flags+='+'
  (( modified )) && flags+='!'
  (( untracked )) && flags+='?'
  _git_info=" on %B%F{magenta} ${branch//\%/%%}%f%b"
  [[ -n $flags ]] && _git_info+=" %B%F{red}[$flags]%f%b"
}

# Current kube context and namespace, re-read only when the kubeconfig changes
zmodload -F zsh/stat b:zstat
function _prompt_kube {
  (( $+commands[kubectl] )) && [[ -f ${KUBECONFIG%%:*} ]] || { _kube_info=''; return }
  local mtime
  mtime=$(zstat +mtime -- "${KUBECONFIG%%:*}" 2>/dev/null)
  [[ $mtime == $_kube_mtime ]] && return
  _kube_mtime=$mtime
  local ctx ns
  ctx=$(kubectl config current-context 2>/dev/null) || { _kube_info=''; return }
  ns=$(kubectl config view --minify -o 'jsonpath={..namespace}' 2>/dev/null)
  _kube_info=" on %F{green}%2{⛵%} ${ctx//\%/%%} (${${ns:-default}//\%/%%})%f"
}

function _prompt_precmd {
  local exit_status=$?
  _prompt_git
  _prompt_kube
  (( exit_status )) && _prompt_color=red || _prompt_color=green
  print # blank line between commands, like starship
}
add-zsh-hook precmd _prompt_precmd
preexec() { echo -ne '\e[6 q' } # beam cursor while a command runs

_prompt_symbol='❯'
_prompt_color=green
PROMPT='%B%F{cyan}%3~%f%b${_git_info}${_kube_info}
%(!.%F{red}#%f .)%B%F{${_prompt_color}}${_prompt_symbol}%f%b '
[[ -n $SSH_CONNECTION ]] && PROMPT='%F{yellow}%n@%m%f in '$PROMPT

####################
# Aliases
####################
if ls --color=auto -d / >/dev/null 2>&1; then # GNU ls
  alias ls='ls --color=auto'
  alias ll='ls -lh --color=auto --group-directories-first'
  alias la='ls -alh --color=auto --group-directories-first'
else # BSD ls
  alias ls='ls -G'
  alias ll='ls -lhG'
  alias la='ls -alhG'
fi
alias grep='grep --color=auto'

if (( $+commands[nvim] )); then
  alias vim=nvim vi=nvim
  alias svim='sudo -E nvim'
fi
(( $+commands[lazygit] )) && alias lg=lazygit
alias load-zshrc='source ~/.zshrc'

# git
alias gp='git pull'
alias gco='git checkout'
alias gcom='git checkout master'

# terraform
alias tfp='TF_CLI_ARGS_plan="-compact-warnings" terraform plan -lock=false -refresh=false'

# kubectl
if (( $+commands[kubectl] )); then
  alias k=kubectl
  alias sk='kubectl -n kube-system'
  alias kaf='kubectl apply -f'
  alias keit='kubectl exec -it'
  alias kl='kubectl logs'
  alias kgp='kubectl get pods'
  alias kdp='kubectl describe pods'
  alias kgs='kubectl get svc'
  alias kgss='kubectl get secrets'
  alias kgd='kubectl get deployment'
  # kubectx/kubens replacements
  kctx() { (( $# )) && kubectl config use-context "$1" || kubectl config get-contexts }
  kns() { (( $# )) && kubectl config set-context --current --namespace="$1" || kubectl get namespaces }
fi

####################
# Functions
####################
take() { mkdir -p -- "$@" && cd -- "${@[-1]}" }

json_2_env() { jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' }

k8s_decrypt_secret() { kubectl get secret "$1" -o json | jq -r '.data | map_values(@base64d)' }

tmuxstart() {
  local s
  for s in base focus service playground; do
    tmux has-session -t "$s" 2>/dev/null || tmux new-session -d -s "$s"
  done
  tmux attach-session -t base
}

# Machine-specific additions that shouldn't live in this file
if [[ -f $HOME/.zshrc.local ]]; then source "$HOME/.zshrc.local"; fi
