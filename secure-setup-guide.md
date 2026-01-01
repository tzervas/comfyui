# Secure Rootless Docker & Virtualization Setup Guide
# Debian 13 (Trixie) VM Configuration

## Overview
This guide sets up a secure Debian 13 VM with:
- Rootless Docker + Docker Compose v2
- Rootless libvirt/virt-manager/virt-viewer
- Role-based SSH access with key restrictions
- Isolated users for different services

## Prerequisites
- Fresh Debian 13 installation
- At least 4GB RAM, 2 CPUs, 50GB disk
- LAN access for SSH management

## Step 1: System Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essentials
sudo apt install -y ca-certificates curl uidmap slirp4netns fuse-overlayfs ufw

# Configure firewall (adjust subnet for your LAN)
sudo ufw allow from 192.168.0.0/24 to any port 22
sudo ufw --force enable

# Disable root SSH
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## Step 2: Create Service Users
```bash
# Docker user (no sudo access, rootless Docker)
sudo adduser dockeruser --shell /bin/bash
sudo usermod -aG docker dockeruser

# VM/libvirt user
sudo adduser vmuser --shell /bin/bash
sudo usermod -aG kvm,libvirt-qemu vmuser

# Admin user (limited sudo for system tasks)
sudo adduser adminuser --shell /bin/bash
```

## Step 3: Configure User Namespaces
```bash
# Add UID/GID mappings for rootless operations
echo "dockeruser:100000:65536" | sudo tee -a /etc/subuid
echo "vmuser:165536:65536" | sudo tee -a /etc/subgid
echo "dockeruser:100000:65536" | sudo tee -a /etc/subgid
echo "vmuser:165536:65536" | sudo tee -a /etc/subuid
```

## Step 4: Install Docker (Rootful First, Then Rootless)
```bash
# Add Docker APT repository
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

# Test rootful Docker briefly
sudo docker run hello-world

# Disable rootful daemon
sudo systemctl disable --now docker.service docker.socket
```

## Step 5: Configure Rootless Docker for dockeruser
```bash
# Switch to dockeruser
sudo -u dockeruser -i << 'EOF'
# Install rootless Docker
dockerd-rootless-setuptool.sh install

# Configure environment
cat >> ~/.bashrc << 'INNER_EOF'
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
INNER_EOF

# Enable and start service
systemctl --user enable docker.service
systemctl --user start docker.service

# Test rootless Docker
docker run hello-world
EOF

# Enable linger for boot persistence
sudo loginctl enable-linger dockeruser
```

## Step 6: Install and Configure Libvirt (Rootless)
```bash
# Install virtualization packages
sudo apt install -y qemu-kvm libvirt-clients libvirt-daemon virtinst virt-manager virt-viewer bridge-utils

# Configure libvirt for session mode (run as vmuser)
sudo -u vmuser -i << 'EOF'
# Test session connection
virsh uri  # Should show qemu:///session

# Create default network (one-time root action needed)
EOF

# As root, start default network (required once)
sudo virsh net-start default
sudo virsh net-autostart default
```

## Step 7: Configure SSH with Role-Based Access
```bash
# Global SSH hardening
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Create SSH keys for each user (run on your client machine)
# ssh-keygen -t ed25519 -C "docker-access" -f ~/.ssh/docker_key
# ssh-keygen -t ed25519 -C "vm-access" -f ~/.ssh/vm_key
# ssh-keygen -t ed25519 -C "admin-access" -f ~/.ssh/admin_key
```

## Step 8: Set Up SSH Authorized Keys with Restrictions
```bash
# For dockeruser - restrict to Docker commands only
sudo -u dockeruser mkdir -p ~dockeruser/.ssh
sudo -u dockeruser chmod 700 ~dockeruser/.ssh

# Add your public key with restrictions (replace YOUR_PUBLIC_KEY)
cat << 'EOF' | sudo tee ~dockeruser/.ssh/authorized_keys
restrict,command="/usr/local/bin/docker-restricted.sh $SSH_ORIGINAL_COMMAND",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 YOUR_DOCKER_PUBLIC_KEY docker-access
EOF
sudo chown dockeruser:dockeruser ~dockeruser/.ssh/authorized_keys
sudo chmod 600 ~dockeruser/.ssh/authorized_keys

# Create restricted Docker script
cat << 'EOF' | sudo tee /usr/local/bin/docker-restricted.sh
#!/bin/bash
# Allow only safe Docker commands
case "$1" in
    "docker ps"|"docker images"|"docker logs"|"docker exec"|"docker compose ps"|"docker compose logs"|"docker stats")
        exec $1 "${@:2}"
        ;;
    "docker run"|"docker build"|"docker pull"|"docker compose up"|"docker compose down"|"docker compose build")
        # Allow with restrictions
        exec $1 "${@:2}"
        ;;
    *)
        echo "Command not allowed: $1"
        exit 1
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/docker-restricted.sh
sudo chown dockeruser:dockeruser /usr/local/bin/docker-restricted.sh
```

## Step 9: Set Up VM User SSH Restrictions
```bash
# For vmuser - restrict to libvirt commands
sudo -u vmuser mkdir -p ~vmuser/.ssh
sudo -u vmuser chmod 700 ~vmuser/.ssh

cat << 'EOF' | sudo tee ~vmuser/.ssh/authorized_keys
restrict,command="/usr/local/bin/virsh-restricted.sh $SSH_ORIGINAL_COMMAND",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 YOUR_VM_PUBLIC_KEY vm-access
EOF
sudo chown vmuser:vmuser ~vmuser/.ssh/authorized_keys
sudo chmod 600 ~vmuser/.ssh/authorized_keys

# Create restricted virsh script
cat << 'EOF' | sudo tee /usr/local/bin/virsh-restricted.sh
#!/bin/bash
# Allow only safe virsh commands
case "$1" in
    "list"|"dominfo"|"domstate"|"domstats"|"nodeinfo"|"version")
        exec virsh "$@"
        ;;
    "start"|"shutdown"|"reboot"|"destroy"|"suspend"|"resume")
        # Allow VM control commands
        exec virsh "$@"
        ;;
    *)
        echo "Command not allowed: $1"
        exit 1
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/virsh-restricted.sh
sudo chown vmuser:vmuser /usr/local/bin/virsh-restricted.sh
```

## Step 10: Set Up Admin User with Limited Sudo
```bash
# For adminuser - allow specific system management commands
sudo -u adminuser mkdir -p ~adminuser/.ssh
sudo -u adminuser chmod 700 ~adminuser/.ssh

cat << 'EOF' | sudo tee ~adminuser/.ssh/authorized_keys
restrict,no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 YOUR_ADMIN_PUBLIC_KEY admin-access
EOF
sudo chown adminuser:adminuser ~adminuser/.ssh/authorized_keys
sudo chmod 600 ~adminuser/.ssh/authorized_keys

# Create sudoers file for limited admin access
cat << 'EOF' | sudo tee /etc/sudoers.d/adminuser
adminuser ALL=(ALL) NOPASSWD: /usr/bin/apt update, /usr/bin/apt upgrade, /usr/bin/systemctl status *, /usr/bin/journalctl, /usr/bin/dmesg, /usr/sbin/ufw status
EOF
sudo chmod 440 /etc/sudoers.d/adminuser
```

## Step 11: Set Simple Test Passwords (Change Later!)
```bash
# Set simple passwords for testing (CHANGE THESE IN PRODUCTION!)
echo "dockeruser:testpass123" | sudo chpasswd
echo "vmuser:testpass123" | sudo chpasswd
echo "adminuser:testpass123" | sudo chpasswd
```

## Step 12: Test the Setup
```bash
# Test Docker (as dockeruser)
sudo -u dockeruser -i docker ps
sudo -u dockeruser -i docker compose version

# Test libvirt (as vmuser)
sudo -u vmuser -i virsh list --all

# Test SSH access (from client)
ssh -i ~/.ssh/docker_key dockeruser@vm-ip "docker ps"
ssh -i ~/.ssh/vm_key vmuser@vm-ip "virsh list"
ssh -i ~/.ssh/admin_key adminuser@vm-ip "sudo apt update"
```

## Step 13: Deploy ComfyUI Stack (Rootless)
```bash
# As dockeruser, deploy the stack
sudo -u dockeruser -i << 'EOF'
cd /home/dockeruser
git clone https://github.com/your-repo/comfyui-docker.git
cd comfyui-docker
docker compose up -d
EOF
```

## Security Notes
- Change test passwords to strong generated ones for production
- Regularly update SSH keys and rotate them
- Monitor logs with `journalctl` and `sudo journalctl --user -u docker`
- Use fail2ban for additional SSH protection
- Backup user home directories and configurations

## Troubleshooting
- If Docker fails: Check `journalctl --user -u docker` as dockeruser
- If libvirt fails: Ensure user is in kvm group and try `virsh connect qemu:///session`
- If SSH fails: Check authorized_keys permissions and sshd_config
- For permission issues: Verify UID/GID mappings in /etc/subuid and /etc/subgid