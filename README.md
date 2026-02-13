# Ansible Homelab

Ansible playbooks that configure a Mac Mini M1 running Fedora Asahi Remix 42
(aarch64) as a development machine and personal server.
The multi-playbook layout also supports targeting remote servers with a subset
of roles.

## What gets configured

### Security

Hardened sshd_config (key-only auth, no root login, max 2 retries,
restricted ciphers/MACs/KexAlgorithms), firewalld (ssh + mosh),
fail2ban (1 h ban after 3 failures), SELinux enforcing, dnf-automatic
for unattended updates.

### Dev environment

System packages, CLI tools (ripgrep, fd, bat, fzf, jq, yq, zoxide, direnv,
eza, lazygit, yazi, starship, sops), Go (latest from go.dev), Node.js, Neovim
with LazyVim, Fish shell, Tmux with TPM, GPG agent (doubling as SSH agent),
Git with delta, JetBrains Mono Nerd Font, Catppuccin Macchiato theming across
foot terminal, bat, starship, delta, and fish.

### Essential services

Tailscale VPN (official repo, not Fedora's stale package), Syncthing file sync
(binary from GitHub, systemd user service).

### Home server

Podman containers running as user services (no root containers).
Immich photo management (server + ML + Redis + pgvecto-rs Postgres).
Nextcloud (app + Redis + Postgres, 16 GB upload limit).
SOPS + age secrets decrypted to tmpfs at `/run/user/<uid>/secrets/` so
credentials never hit disk.

All HTTP services are accessible only via Tailscale — no TLS termination
needed, no ports exposed to the public internet.

## Prerequisites

1. Ansible:

   ```bash
   sudo dnf install ansible
   ```

2. Required collections:

   ```bash
   ansible-galaxy collection install community.general ansible.posix
   ```

3. Age key at `~/.config/sops/age/keys.txt` for secrets decryption.

4. SOPS-encrypted secrets at `~/.config/sops-secrets/secrets.yaml`.

## Usage

### Full setup

```bash
ansible-playbook site.yml --ask-become-pass
```

This runs all playbooks in order: bootstrap, security, dev, essentials,
homeserver.

### Dry run

```bash
ansible-playbook site.yml --ask-become-pass --check --diff
```

### Individual playbooks

```bash
# Just dev tools:
ansible-playbook playbooks/dev.yml --ask-become-pass

# Just security hardening:
ansible-playbook playbooks/security.yml --ask-become-pass

# Just essential services:
ansible-playbook playbooks/essentials.yml --ask-become-pass

# Just home server (podman, secrets, immich, nextcloud):
ansible-playbook playbooks/homeserver.yml --ask-become-pass
```

### Remote server (security + essentials only)

```bash
ansible-playbook playbooks/security.yml playbooks/essentials.yml \
  -i inventories/remote-server/ --ask-become-pass
```

### Specific roles via tags

```bash
ansible-playbook site.yml --ask-become-pass --tags "fish,tmux"
ansible-playbook playbooks/homeserver.yml --ask-become-pass --tags "immich"
```

## Enclave users

Enclaves are isolated service accounts with cgroup resource limits. Each gets
its own user, home directory, systemd slice, and linger — ready for deploying
containerised workloads.

### Add a new enclave

1. Add an entry to the `enclaves` list in `vars/main.yml`:
   ```yaml
   enclaves:
     - name: my-service
       memory_max: "12G"
       cpu_quota: "600%"
       tasks_max: 512
   ```

2. Run the playbook:
   ```bash
   ansible-playbook site.yml --ask-become-pass --tags enclave
   ```

### Get a shell inside an enclave

Enclave users have `/usr/sbin/nologin` as their shell, so use `sudo` to run
commands as them:

```bash
# Interactive shell
sudo -u my-service bash

# Single command
sudo -u my-service ls -la /home/my-service/
```

### Remove an enclave

```bash
sudo ./scripts/remove-enclave.sh my-service
```

This stops the cgroup slice (killing all processes), disables linger, removes
the user and home directory, cleans up systemd artifacts, and reloads systemd.

After removing, also delete the entry from `vars/main.yml` so Ansible doesn't
recreate it on the next run.

## Post-run manual steps

1. **Tailscale** (first time): `sudo tailscale up`
2. **Tmux plugins**: open tmux, press `prefix + I` (Ctrl-a, Shift-i)
3. **Neovim plugins**: open neovim — LazyVim auto-installs on first launch
4. **GPG keys**: `gpg --import your-key.asc`

## Architecture

### Secrets management

Runtime secrets use SOPS + age, not Ansible Vault.
A systemd user service (`decrypt-secrets.service`) runs at boot, decrypts
`~/.config/sops-secrets/secrets.yaml` with the age key, and writes individual
env files to `/run/user/<uid>/secrets/` (tmpfs, mode 600).
Container compose files reference these env files.

### Service deployment

Everything runs as systemd user services — no root-owned containers.
`loginctl enable-linger` (set by `bootstrap.yml`) ensures user services start
at boot without requiring a login session.

Services: gpg-agent, syncthing, decrypt-secrets, immich, nextcloud.

### Network security

No ports are exposed to the public internet.
Immich (port 2283) and Nextcloud (port 8080) are reachable only over Tailscale.
SSH and mosh are the only firewalld-allowed services.

## Directory structure

```
ansible-homelab/
  ansible.cfg
  site.yml                         # imports all playbooks
  inventories/
    home-server/hosts              # localhost (Mac Mini M1)
    remote-server/hosts            # placeholder for remote hosts
  playbooks/
    bootstrap.yml                  # dnf cache, loginctl linger
    security.yml                   # role: security
    enclaves.yml                   # Loops over enclaves list → enclave role
    dev.yml                        # roles: base, dev-tools, user-scripts,
                                   #   golang, nodejs, fonts, catppuccin,
                                   #   gpg, git, neovim, fish, tmux
    essentials.yml                 # roles: tailscale, syncthing
    homeserver.yml                 # roles: podman, secrets, immich, nextcloud
  vars/
    main.yml                       # shared variables (versions, paths, ports)
    personal.yml                   # gitignored PII (user, email, timezone)
    personal.yml.example           # template for personal.yml
    secrets.yml                    # placeholder (actual secrets via SOPS)
  roles/
    base/                          # system packages, ~/.local/bin
    dev-tools/                     # CLI tools (dnf + GitHub binaries)
    user-scripts/                  # ,update script for syncthing/go/claude
    golang/                        # latest Go from go.dev
    nodejs/                        # Node.js + npm global prefix
    neovim/                        # Neovim + LazyVim init.lua
    fish/                          # Fish shell + config + Catppuccin theme
    git/                           # Git + delta + Catppuccin delta theme
    tmux/                          # Tmux + TPM + config
    gpg/                           # GnuPG + gpg-agent + systemd user units
    fonts/                         # JetBrains Mono Nerd Font
    catppuccin/                    # Catppuccin Macchiato (foot, bat, starship)
    tailscale/                     # Tailscale VPN (official repo)
    syncthing/                     # Syncthing (GitHub binary, user service)
    podman/                        # Podman + podman-compose
    secrets/                       # SOPS + age decrypt-secrets service
    immich/                        # Immich compose + user service
    nextcloud/                     # Nextcloud compose + user service
    security/                      # SSH, firewalld, fail2ban, SELinux, auto-updates
    enclave/                       # Isolated user + cgroup slice
  scripts/
    remove-enclave.sh              # Tear down an enclave user
```

## Idempotency

All playbooks are safe to re-run.
Tasks use `state: present` for packages, `creates`/`stat` guards for
downloads, templates that only write on content change, and `notify` handlers
for service restarts only when something actually changed.
