#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in a git repository
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Current directory is not a git repository (.git directory not found)${NC}"
    exit 1
fi

# Check if we're on the archiso branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "archiso" ]]; then
    echo -e "${RED}Error: Not on archiso branch (current: $current_branch)${NC}"
    exit 1
fi

# Check if there are untracked files (git clean -xfd should have been run)
if [[ -n $(git ls-files --others --exclude-standard) ]]; then
    echo -e "${RED}Error: Untracked files found. Please run 'git clean -xfd' first:${NC}"
    git ls-files --others --exclude-standard
    exit 1
fi

# Get archiso version from pacman
archiso_version=$(pacman -Q archiso | awk '{print $2}')
if [[ -z "$archiso_version" ]]; then
    echo -e "${RED}Error: Could not determine archiso version${NC}"
    exit 1
fi

# Source and destination paths
source_path="/usr/share/archiso/configs/releng/"
dest_path="."

# Check if source exists
if [[ ! -d "$source_path" ]]; then
    echo -e "${RED}Error: Source directory $source_path does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}Updating from archiso version $archiso_version${NC}"
echo -e "${YELLOW}Source: $source_path${NC}"
echo -e "${YELLOW}Destination: $dest_path${NC}"

# Perform rsync with exclusions
rsync -av --delete \
    --exclude='.git' \
    --exclude='update-from-archiso.sh' \
    "$source_path" "$dest_path"

echo -e "${GREEN}Update completed successfully${NC}"

# Generate commit message
commit_message="archiso $archiso_version"
echo -e "${GREEN}Suggested commit message:${NC}"
echo "$commit_message"
