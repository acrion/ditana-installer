#!/usr/bin/env bash

# This script checks for the presence of .bashrc_ditana at each login.
# If found, it replaces the existing .bashrc (copied from /etc/skel during user account creation) with .bashrc_ditana.
# This ensures that the standard .bashrc is replaced by the customized .bashrc_ditana for enhanced user configurations.
# Note that /etc/skel/.bashrc cannot be changed, because it is part of the package `bash`.
if [ -f "$HOME/.bashrc_ditana" ]; then
    mv "$HOME/.bashrc_ditana" "$HOME/.bashrc"
fi
