#!/usr/bin/env bash

# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of Ditana Installer, see
# https://github.com/acrion/ditana-installer and https://ditana.org/installer.
#
# Ditana Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ditana Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ditana Installer. If not, see <https://www.gnu.org/licenses/>.

shopt -s dotglob
cd "$HOME"
source settings.sh
export PATH="$HOME/.raku/bin:$PATH"

{
    set -e
    
    mount -a

    echo -e "\033[32m--- Configuring Arch multilib repository --- \033[0m"
    s6 --task-run sparrow/tasks/pacman@enable_multilib=$ENABLE_MULTILIB
    ./enable-chaotic-aur.sh "$ENABLE_CHAOTIC_AUR"
    echo -e "\033[32m--- Enabling the Ditana repository --- \033[0m"
    ./enable-ditana.sh
    echo -e "\033[32m--- Signing Ditana repository --- \033[0m"
    ./sign-ditana.sh
    echo -e "\033[32m--- Syncing new repositories ---\033[0m"
    pacman -Sy # Sync multilib and chaotic-aur

    if ! getent group "$USER_GROUP"; then
        groupadd -g "$USER_GROUP" "$USER_NAME"
    fi

    echo -e "\033[32m--- Configuring umask ---\033[0m"
    if [[ "$UMASK_027" == "y" ]]; then
        sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs
    elif [[ "$UMASK_077" == "y" ]]; then
        sed -i 's/^UMASK.*/UMASK\t\t077/' /etc/login.defs
    fi
    # umask-022: no change needed, 022 is the default in /etc/login.defs
    
    echo -e "\033[32m--- Creating user $USER_NAME with UID $USER_ID and GID $USER_GROUP ---\033[0m"
    useradd -m -u "$USER_ID" -g "$USER_GROUP" "$USER_NAME"
    
    # Create the temporary builduser. We need it to use makepkg and pikaur
    echo -e "\033[32m--- Creating temporary build user ---\033[0m"
    useradd -m builduser
    usermod -aG wheel builduser
    TEMP_SUDOERS=$(mktemp)
    echo 'builduser ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/pikaur' > "$TEMP_SUDOERS"
    echo 'Defaults:builduser env_keep += "EDITOR"' >> "$TEMP_SUDOERS"

    if visudo -c -f "$TEMP_SUDOERS"; then
        mv "$TEMP_SUDOERS" /etc/sudoers.d/builduser
        chmod 0440 /etc/sudoers.d/builduser
        echo -e "\033[32mSudoers file for builduser created and verified successfully.\033[0m"
    else
        cat "$TEMP_SUDOERS"
        echo -e "\033[32mError in sudoers file syntax. No changes were made.\033[0m"
        rm "$TEMP_SUDOERS"
        userdel -r builduser
        exit 1
    fi

    source installation-steps.sh

    # restore current directory (potentially changed by installation-steps.sh)
    cd $HOME

    # Spell checker installation (locale-dependent, kept here for simplicity)
    LOWERCASE_LOCALE=$(echo "$LOCALE" | tr '[:upper:]' '[:lower:]')
    SPELL_CHECKER="hunspell-$LOWERCASE_LOCALE"

    if ! is_package_available "$SPELL_CHECKER"; then
        SPELL_CHECKER="hunspell-$MAIN_LOCALE"
    fi

    if is_package_available "$SPELL_CHECKER"; then
        runuser -u builduser -- pikaur -S "$SPELL_CHECKER" --noconfirm || true
        echo -e "\033[32m--- Installing spell checker '$SPELL_CHECKER' for $LOWERCASE_LOCALE ---\033[0m"
    else
        echo -e "\033[33m--- Unable to install spell checker for $MAIN_LOCALE because '$SPELL_CHECKER' is not available ---\033[0m"
    fi

    source ./install-and-configure-bootloader.sh

    # After AUR builds, typically `keyboxd --homedir /home/builduser/.gnupg --daemon` is running and prevents builduser from being removed
    runuser -u builduser -- gpgconf --kill all || true

    while ! userdel -r builduser
    do
        echo -e "\033[32mProcesses still running under builduser:\033[0m"
        pgrep -u builduser -a || true
        echo -e "\033[32mOpen files / sockets for builduser:\033[0m"
        lsof -u builduser || true
        pkill -9 -u builduser || true
        sleep 1
    done
    echo -e "\033[32m--- Successfully deleted temporary build user ---\033[0m"
    rm /etc/sudoers.d/builduser
    echo -e "\033[32m--- Adding $USER_NAME to wheel group ---\033[0m"
    usermod -aG wheel "$USER_NAME" # Note file 99-wheel-group installed by package ditana-filesystem

    touch /var/log/chroot_installation_finished
    echo -e "\033[32m--- Leaving subshell in chroot-install.sh ---\033[0m"    
} 2>&1 | tee -a /var/log/install_ditana.log

if [[ ! -f /var/log/chroot_installation_finished ]]; then
    echo "Exiting chroot-install.sh with an error." | tee -a /var/log/install_ditana.log
    sync
    exit 1
fi

is_secure_password() {
    local PASSPHRASE="$1"
    local MIN_SCORE="${2:-67}"
    local PWSCORE_RESULT

    if ! PWSCORE_RESULT=$(pwscore <<< "$PASSPHRASE" 2>&1); then
        # pwscore prints an explanation in this case
        echo "$PWSCORE_RESULT"
        return 1
    elif ! [[ "$PWSCORE_RESULT" =~ ^[0-9]+$ ]]; then
        # We expect pwscore to only output a number if it is successful. If this property of pwscore has been changed or is not reliable, we will only perform the above basic check.
        return 0
    elif [[ $PWSCORE_RESULT -lt $MIN_SCORE ]]; then
        echo "Your password is $((MIN_SCORE - PWSCORE_RESULT)) % below the minimum security requirements."
        echo "For a stronger password, use a mix of uppercase and lowercase letters, numbers, and special characters."
        return 1
    fi
    return 0
}

cd "$HOME"
set +e

while true; do
    echo "Prompting the user to enter a password." >> /var/log/install_ditana.log
    if    ! USER_PASSWORD=$(dialog --stdout --insecure --passwordbox "Please enter a password for user $USER_NAME" 10 50) \
       || [[ -z "$USER_PASSWORD" ]]
    then
        echo "User entered empty password." >> /var/log/install_ditana.log
        dialog --msgbox "Please specify a password." 10 50
        continue
    fi

    if ! PW_OUTPUT=$(is_secure_password "$USER_PASSWORD" 2>&1); then
        echo "User entered insecure password." >> /var/log/install_ditana.log
        
        # Ask user if they want to use the insecure password anyway
        if dialog --title 'Insecure Password' --yes-label 'Enter Secure Password' --no-label 'Use Anyway' \
                  --yesno "$PW_OUTPUT\n\nWould you like to enter a more secure password?" 10 80
        then
            echo "User chose to enter a more secure password." >> /var/log/install_ditana.log
            continue
        else
            echo "User chose to use insecure password anyway." >> /var/log/install_ditana.log
        fi
    fi

    echo "Prompting the user to confirm the password." >> /var/log/install_ditana.log
    if CONFIRM_PASSWORD=$(dialog --stdout --insecure --passwordbox "Please confirm the password" 10 50)
    then
        if [[ "$USER_PASSWORD" == "$CONFIRM_PASSWORD" ]]; then
            chpasswd <<< "${USER_NAME}:${USER_PASSWORD}"
            unset USER_PASSWORD CONFIRM_PASSWORD
            echo "Set user password." >> /var/log/install_ditana.log
            break
        else
            echo "Passwords do not match." >> /var/log/install_ditana.log
            dialog --msgbox "Passwords do not match. Please try again." 10 50
        fi
    fi
done

clear

{
    if [[ "$CONFIGURE_AUTOMATIC_SNAPSHOTS" == "y" ]]; then
        if [[ "$ZFS_FILESYSTEM" == "y" ]]; then
            echo -e "\033[32m--- Creating first ZFS snapshot ---\033[0m"
            zfs snapshot ditana-root/ROOT/default@autosnap_after_ditana_installation
        else
            echo -e "\033[32m--- Configuring Timeshift and creating first snapshot ---\033[0m"
            comments="after installation of Ditana GNU/Linux"

            if [[ "$BTRFS_FILESYSTEM" == "y" ]]; then
                timeshift --create --btrfs --comments "$comments" --scripted
            else
                ROOT_UUID="$(findmnt -no UUID /)"
                echo "ROOT_UUID = $ROOT_UUID"
                timeshift --create --rsync --comments "$comments" --scripted --snapshot-device UUID="$ROOT_UUID"
            fi
        fi
        echo -e "\033[32m--- Finished first snapshot ---\033[0m"
    fi    
} 2>&1 | tee -a /var/log/install_ditana.log

echo "Showing dialog: The system installation is finished, please confirm to reboot." >>/var/log/install_ditana.log
dialog --msgbox "The system installation is finished, please confirm to reboot." 10 50
clear

sync >>/var/log/install_ditana.log
