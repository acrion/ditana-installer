HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000
setopt nomatch
unsetopt autocd beep extendedglob
bindkey -e

zstyle :compinstall filename "$HOME/.zshrc"

autoload -Uz compinit
compinit

if command -v starship > /dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

if command -v fzf > /dev/null 2>&1; then
    eval "$(fzf --zsh)"
fi

[[ -f /usr/share/doc/pkgfile/command-not-found.zsh ]] && \
    source /usr/share/doc/pkgfile/command-not-found.zsh

# Repair delete-character key for zsh, see `man terminfo` and `man zshzle`.
bindkey -M emacs "${terminfo[kdch1]}" delete-char
bindkey -M viins "${terminfo[kdch1]}" delete-char
bindkey -M vicmd "${terminfo[kdch1]}" delete-char

# Repair home key for zsh. In kitty, these differ from "${terminfo[khome]}",
# see `cat -v` and `infocmp -1 | grep -E "khome"`.
bindkey -M emacs '\e[H' beginning-of-line
bindkey -M viins '\e[H' beginning-of-line
bindkey -M vicmd '\e[H' beginning-of-line
# Fallback
bindkey -M emacs '\eOH' beginning-of-line
bindkey -M viins '\eOH' beginning-of-line
bindkey -M vicmd '\eOH' beginning-of-line

# Repair end key for zsh. In kitty, these differ from "${terminfo[kend]}",
# see `cat -v` and `infocmp -1 | grep -E "kend"`.
bindkey -M emacs '\e[F' end-of-line
bindkey -M viins '\e[F' end-of-line
bindkey -M vicmd '\e[F' end-of-line
# Fallback
bindkey -M emacs '\eOF' end-of-line
bindkey -M viins '\eOF' end-of-line
bindkey -M vicmd '\eOF' end-of-line

source "$HOME/.shellrc"
