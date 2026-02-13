#!/usr/bin/env bash
# Remove an enclave user and all its systemd/cgroup artifacts.
# Usage: sudo ./scripts/remove-enclave.sh <username>

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <enclave-username>"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (sudo)."
    exit 1
fi

NAME="$1"

# Validate name format (same regex as the Ansible role)
if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Error: '$NAME' doesn't look like a valid enclave name."
    exit 1
fi

# Look up UID before deleting the user
if ! UID_NUM=$(id -u "$NAME" 2>/dev/null); then
    echo "Error: user '$NAME' does not exist."
    exit 1
fi

echo "Removing enclave '$NAME' (UID $UID_NUM)..."

# 1. Stop the enclave slice (kills all processes inside it)
if systemctl is-active --quiet "enclave-${NAME}.slice" 2>/dev/null; then
    echo "  Stopping enclave-${NAME}.slice..."
    systemctl stop "enclave-${NAME}.slice"
fi

# 2. Disable linger
if [[ -f "/var/lib/systemd/linger/${NAME}" ]]; then
    echo "  Disabling linger..."
    loginctl disable-linger "$NAME"
fi

# 3. Remove the user and home directory
echo "  Removing user and /home/${NAME}..."
userdel -r "$NAME" 2>/dev/null || true

# 4. Remove systemd slice and user-slice override
echo "  Removing systemd artifacts..."
rm -f "/etc/systemd/system/enclave-${NAME}.slice"
rm -rf "/etc/systemd/system/user-${UID_NUM}.slice.d"

# 5. Reload systemd
systemctl daemon-reload

echo "Done. Enclave '$NAME' fully removed."
