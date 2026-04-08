# .shell.d Directory

## Overview
This directory, `.shell.d`, is part of the Ditana GNU/Linux shell configuration system. It is designed to store executable shell scripts that are automatically loaded into your shell environment (both bash and zsh) when a new terminal session is initiated.

## Purpose
The scripts in this directory are sourced by `.shellrc`, which is included in your home directory. This setup allows you to maintain a clean and organized shell configuration by separating your custom commands and configurations into distinct, executable scripts that work across both bash and zsh.

## Usage
To effectively use this directory:
1. Place any shell script you want automatically executed in this directory.
2. Ensure the scripts are executable (`chmod +x script_name.sh`).
3. Use syntax compatible with both bash and zsh.
4. Scripts will be sourced each time a new terminal is opened.

## Compatibility
Scripts in this directory should be compatible with both zsh and bash. When writing scripts, use syntax that works in both shells to ensure consistent behavior.

## Security Note
Only place trusted scripts in this directory. All scripts here are automatically executed when opening a terminal, so manage the contents carefully to avoid unintentional execution of harmful commands.

## Example
Here's a sample script that could be placed in this directory:

```bash
#!/bin/bash
# This script sets up aliases for common commands

alias grep='ugrep'
alias cat='bat'
alias ls='exa --icons --classify --hyperlink --group-directories-first'

# Conditional alias for SSH in Kitty terminal
if [[ "$TERM" == "xterm-kitty" ]]; then
    alias ssh='kitten ssh'
fi
```

Save this as an executable file (e.g., `00-aliases.sh`) in the `.shell.d` directory to have these aliases available in all your terminal sessions.
Ensure to make it executable (`chmox +d <script name>`).

## Support
For issues or questions regarding the Ditana shell configuration, please refer to the Ditana GNU/Linux documentation or support channels.
