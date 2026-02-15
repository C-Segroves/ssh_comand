#!/usr/bin/env bash
# setup-ssh-for-lan.sh
# Single-file script to prepare fresh Linux Mint for key-based SSH access from your LAN command server
# Run as:   wget -O - https://your-pastebin-or-github/raw/setup-ssh-for-lan.sh | bash    OR   just copy-paste into terminal
# Best run right after fresh install, as your normal user with sudo access

set -euo pipefail

echo ""
echo "=== Linux Mint SSH Setup for LAN Command Runner ==="
echo "This will install OpenSSH server and prepare for passwordless (key-based) access."
echo "You will need to run 'ssh-copy-id' FROM your main computer afterward."
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 1. Update & install openssh-server
# ──────────────────────────────────────────────────────────────────────────────
echo "→ Updating package list and installing openssh-server..."
sudo apt update -y
sudo apt install -y openssh-server

echo "→ Ensuring SSH service is running and enabled on boot..."
sudo systemctl enable --now ssh

# Quick status check
if systemctl is-active --quiet ssh; then
    echo "SSH server is active ✓"
else
    echo "Error: SSH service failed to start!"
    sudo systemctl status ssh --no-pager
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. Create a dedicated automation user? (recommended)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
read -p "Create a dedicated low-privilege user for SSH commands? (recommended) [Y/n]: " create_user
create_user=${create_user:-Y}

if [[ "${create_user^^}" == "Y" || "${create_user^^}" == "YES" ]]; then
    read -p "Enter username for automation (e.g. lan-auto) [default: lan-auto]: " auto_user
    auto_user=${auto_user:-lan-auto}

    if id "$auto_user" &>/dev/null; then
        echo "User $auto_user already exists — skipping creation."
    else
        echo "→ Creating user $auto_user (no password, no home shell login by default)..."
        sudo adduser --disabled-password --gecos "LAN Automation User" "$auto_user"
        # Optional: allow sudo if you plan to run privileged commands
        read -p "Give $auto_user sudo privileges? (only if needed) [y/N]: " give_sudo
        if [[ "${give_sudo,,}" == "y" ]]; then
            sudo usermod -aG sudo "$auto_user"
            echo "→ Added to sudo group."
        fi
    fi
    ssh_user="$auto_user"
else
    echo "Using your current user: $(whoami)"
    ssh_user="$(whoami)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. Firewall — allow SSH (ufw is usually installed but inactive)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
if command -v ufw &>/dev/null; then
    if sudo ufw status | grep -q "Status: inactive"; then
        echo "ufw is inactive — no change needed for local LAN."
    else
        echo "ufw is active — allowing SSH (port 22)..."
        sudo ufw allow ssh
        sudo ufw reload
    fi
else
    echo "ufw not found — skipping firewall config (assuming no firewall or you handle it)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. Key setup instructions (run FROM your main computer!)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== NEXT STEPS — Run these FROM your MAIN computer (the one with the Flask server) ==="
echo ""
echo "1. If you haven't generated an SSH key yet:"
echo "   ssh-keygen -t ed25519 -C 'lan-command-server'   # or rsa -b 4096"
echo "   (press Enter for defaults, add passphrase if desired)"
echo ""
echo "2. Copy your public key to this machine:"
echo "   ssh-copy-id ${ssh_user}@$(hostname -I | awk '{print $1}')"
echo "   # You will be asked for the ${ssh_user} password ONE TIME only"
echo ""
echo "   If using a non-default key:   ssh-copy-id -i ~/.ssh/yourkey.pub ${ssh_user}@IP"
echo ""
echo "3. Test it works (no password prompt):"
echo "   ssh ${ssh_user}@$(hostname -I | awk '{print $1}') whoami"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 5. Optional: Disable password login (after keys work!)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
read -p "Disable password authentication now? (do this AFTER keys work!) [y/N]: " disable_pw
if [[ "${disable_pw,,}" == "y" ]]; then
    echo "→ Disabling password login in /etc/ssh/sshd_config..."
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || true
    sudo systemctl restart ssh
    echo "Password login disabled. Only keys will work now."
else
    echo "Keeping passwords enabled for now — you can disable later."
fi

echo ""
echo "Setup complete on this machine!"
echo "Repeat on every fresh Mint install."
echo "Back on your main server → register each machine in the web interface using user '${ssh_user}' and leave password blank (it will use your key)."
echo ""

exit 0