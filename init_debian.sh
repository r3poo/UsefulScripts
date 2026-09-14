#!/bin/bash

# Script to set up base configuration on debian environment. Edit to adapt to different use cases.


# Exit on any error
set -e

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && [ "$(sudo -n true 2>/dev/null; echo $?)" -ne 0 ]; then
        echo "This script requires sudo privileges."
        exit 1
fi

# Determine the actual user (in case script is run with sudo)
if [ -n "$SUDO_USER" ]; then
        REAL_USER="$SUDO_USER"
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
        REAL_USER="$USER"
        REAL_HOME="$HOME"
fi

echo "==> Updating system packages..."
sudo apt update
sudo apt upgrade -y

echo "==> Installing required packages..."
sudo apt install -y git neovim curl wget openssh-client openssh-server zsh

echo "==> Installing Oh My Zsh for user $REAL_USER..."
# Install Oh My Zsh as the real user
sudo -u "$REAL_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true

echo "==> Setting zsh as default shell for $REAL_USER..."
sudo chsh -s "$(which zsh)" "$REAL_USER"

echo "==> Configuring SSH daemon..."
SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup original config
sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"

# Disable password authentication
if grep -qE "^\s*#?\s*PasswordAuthentication" "$SSHD_CONFIG"; then
        sudo sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
else
        echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
fi

# Disable root login
if grep -qE "^\s*#?\s*PermitRootLogin" "$SSHD_CONFIG"; then
        sudo sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
else
        echo "PermitRootLogin no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
fi

# Validate config
if sudo sshd -t; then
        echo "SSH config is valid. Restarting ssh service..."
        sudo systemctl restart ssh || sudo systemctl restart sshd
else
        echo "ERROR: SSH config is invalid. Restoring backup."
        sudo cp "${SSHD_CONFIG}.backup."* "$SSHD_CONFIG"
        exit 1
fi

echo "==> Setting up SSH authorized keys from GitHub..."
AUTH_KEYS_DIR="$REAL_HOME/.ssh"
AUTH_KEYS_FILE="$AUTH_KEYS_DIR/authorized_keys"

sudo -u "$REAL_USER" mkdir -p "$AUTH_KEYS_DIR"
sudo -u "$REAL_USER" chmod 700 "$AUTH_KEYS_DIR"

# Fetch keys and append (creating the file if it doesn't exist)
curl -fsSL https://github.com/r3poo.keys | sudo -u "$REAL_USER" tee "$AUTH_KEYS_FILE" > /dev/null

sudo -u "$REAL_USER" chmod 600 "$AUTH_KEYS_FILE"

echo "==> Configuring Neovim..."
NVIM_CONFIG_DIR="$REAL_HOME/.config/nvim"
NVIM_INIT_FILE="$NVIM_CONFIG_DIR/init.vim"

# Create parent directories if they don't exist
sudo -u "$REAL_USER" mkdir -p "$NVIM_CONFIG_DIR"

# Write the settings to init.vim
sudo -u "$REAL_USER" tee "$NVIM_INIT_FILE" > /dev/null <<'EOF'
set tabstop=4
set softtabstop=4
set shiftwidth=4
EOF

echo "==> Done!"
echo ""
echo "Summary:"
echo "  - System updated"
echo "  - Installed: git, neovim, curl, wget, ssh, zsh"
echo "  - Oh My Zsh installed for $REAL_USER"
echo "  - Default shell set to zsh for $REAL_USER"
echo "  - SSH: PasswordAuthentication=no, PermitRootLogin=no"
echo "  - SSH keys from github.com/r3poo.keys installed to $AUTH_KEYS_FILE"
echo ""
echo "NOTE: Log out and back in for the shell change to take effect."
