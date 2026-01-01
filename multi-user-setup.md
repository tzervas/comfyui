Comprehensive Immutable Debian System Setup Guide
Table of Contents

System Overview
Prerequisites & Constraints
Filesystem Architecture
Installation Walkthrough
User & Permission Structure
Rootless Docker Configuration
Rootless KVM/QEMU Configuration
GPU Passthrough Setup
Network Configuration
Immutable Root Management
Maintenance & Operations
Troubleshooting


System Overview
Architecture Goals

Immutable root filesystem - Read-only by default, updates via snapshot swapping
BTRFS with compression - zstd compression for all filesystems except boot
Rootless containers & VMs - No privileged Docker/KVM operations
Tightly scoped permissions - Users have minimal necessary access
GPU passthrough capable - VMs can access GPU over network
LAN-accessible services - Docker containers exposed to local network
Dual-boot gaming - Windows VM with GPU passthrough + native Linux gaming

Component Stack
Hardware Layer
├── CPU (with VT-x/AMD-V)
├── GPU (IOMMU groups for passthrough)
└── Storage (BTRFS-formatted)

Filesystem Layer (BTRFS + zstd)
├── /boot (EXT4, untouched)
├── @rootfs (read-only snapshot)
├── @home (read-write)
├── @var (read-write)
├── @docker (read-write, nodatacow)
└── @vms (read-write, nodatacow)

Virtualization Layer
├── KVM/QEMU (rootless per-user sessions)
├── libvirt (user session management)
└── virt-manager (GUI management)

Container Layer
├── Docker (rootless per-user)
├── Docker Compose
└── Networking (bridge, macvlan)

User Layer
├── kang (admin, rootless docker/kvm)
├── spooky (regular, limited docker/kvm)
├── docker-admin (service, full rootless docker)
└── vm-admin (service, full rootless kvm)

Prerequisites & Constraints
Hardware Requirements

CPU: Intel VT-x or AMD-V virtualization support
IOMMU: Intel VT-d or AMD-Vi for GPU passthrough
GPU: Dedicated GPU in isolated IOMMU group (check with find /sys/kernel/iommu_groups/ -type l)
Storage: Minimum 100GB for OS, recommend separate drives for @docker/@vms
RAM: Minimum 16GB (32GB+ recommended for VMs with GPU passthrough)

BIOS/UEFI Settings
Required:
✓ Virtualization Technology (VT-x/AMD-V): Enabled
✓ IOMMU/VT-d/AMD-Vi: Enabled
✓ Secure Boot: Disabled (for VFIO)
✓ CSM/Legacy Boot: Disabled (UEFI only)
✓ Above 4G Decoding: Enabled (for large BARs)
✓ Resizable BAR: Enabled (if available)
Software Prerequisites
bash# Base Debian 13.2 installation
# DO NOT format as BTRFS during initial install - we'll convert
# Use standard EXT4 install, then convert post-install

Required packages:
- btrfs-progs
- qemu-system-x86
- qemu-utils
- libvirt-daemon-system
- libvirt-clients
- virt-manager
- ovmf
- docker.io (to be replaced with rootless)
- uidmap
- slirp4netns
- fuse-overlayfs
```

### Constraints & Design Decisions
1. **Root user disabled**: All admin via sudo with kang user
2. **Read-only root**: System modifications only via chroot snapshots
3. **Rootless priority**: No privileged Docker/KVM unless absolutely necessary
4. **Atomic updates**: Snapshot-based, instant rollback capability
5. **Separation of concerns**: Docker data, VM images, user data all on separate subvolumes
6. **Network isolation**: Rootless networking with selective LAN exposure

---

## Filesystem Architecture

### BTRFS Subvolume Layout
```
/dev/sda (or nvme0n1)
├── /dev/sda1 - EFI System Partition (512MB, FAT32)
├── /dev/sda2 - /boot (1GB, EXT4) - NEVER TOUCH
└── /dev/sda3 - BTRFS root (remaining space)
    ├── @rootfs           → /              (ro,compress=zstd:3)
    ├── @rootfs-update    → /mnt/update    (temporary, for updates)
    ├── @rootfs-backup    → (not mounted)  (previous snapshot)
    ├── @home             → /home          (rw,compress=zstd:3)
    ├── @var              → /var           (rw,compress=zstd:3)
    ├── @docker           → /var/lib/docker (rw,compress=zstd:3,nodatacow)
    ├── @vms              → /var/lib/libvirt (rw,compress=zstd:3,nodatacow)
    └── @snapshots        → /.snapshots    (rw,compress=zstd:3)
```

### Mount Options Explained

**@rootfs (read-only root)**
```
ro,compress=zstd:3,noatime,space_cache=v2,discard=async
```
- `ro`: Read-only, prevents accidental modifications
- `compress=zstd:3`: Compression (3 = balanced speed/ratio)
- `noatime`: Don't update access times (performance)
- `space_cache=v2`: Faster free space tracking
- `discard=async`: SSD TRIM support (if applicable)

**@home, @var (read-write data)**
```
rw,compress=zstd:3,noatime,space_cache=v2,discard=async
```
- `rw`: Read-write for user data and system state

**@docker, @vms (performance-critical)**
```
rw,compress=zstd:3,noatime,space_cache=v2,discard=async,nodatacow
```
- `nodatacow`: Disable copy-on-write for VM images/containers (performance)
- Note: Disables data checksumming for these files

### Subvolume Backup Strategy
```
@rootfs         - Active system (read-only)
@rootfs-backup  - Previous good snapshot (rollback target)
@home           - Backed up externally (user data)
@var            - Ephemeral, logs rotated
@docker         - Container data, backed up selectively
@vms            - VM images, backed up selectively
@snapshots      - Automated snapshots of all subvolumes

Installation Walkthrough
Phase 0: Initial Debian Installation
bash# Install Debian 13.2 with standard EXT4 layout
# During installation:
# - Create user: kang (with sudo)
# - Disk layout: Automatic (entire disk, EXT4)
# - DO NOT configure LVM or manual partitioning yet

# After first boot, update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y btrfs-progs gdisk parted arch-install-scripts rsync
Phase 1: Convert to BTRFS with Subvolumes
⚠️ WARNING: This is destructive. Backup all data first!
bash#!/bin/bash
# convert-to-btrfs.sh - Convert existing Debian install to BTRFS subvolumes

set -euo pipefail

# Identify root partition (usually /dev/sda2 or /dev/nvme0n1p2, NOT /boot)
ROOT_PARTITION="/dev/sda3"  # ADJUST THIS
BOOT_PARTITION="/dev/sda2"
EFI_PARTITION="/dev/sda1"

echo "⚠️  WARNING: This will DESTROY data on $ROOT_PARTITION"
echo "Current mounts:"
lsblk
read -p "Continue? (type 'yes' to proceed): " confirm
[[ "$confirm" != "yes" ]] && exit 1

# 1. Boot from Debian Live USB
# 2. Mount existing system
mkdir -p /mnt/old-root
mount $ROOT_PARTITION /mnt/old-root
mount $BOOT_PARTITION /mnt/old-root/boot
mount $EFI_PARTITION /mnt/old-root/boot/efi

# 3. Backup current system to external drive or tar
echo "Backing up system..."
rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    /mnt/old-root/ /mnt/backup/

# 4. Unmount and reformat as BTRFS
umount -R /mnt/old-root
mkfs.btrfs -f -L debian-root $ROOT_PARTITION

# 5. Create subvolume structure
mount $ROOT_PARTITION /mnt
btrfs subvolume create /mnt/@rootfs
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@docker
btrfs subvolume create /mnt/@vms
btrfs subvolume create /mnt/@snapshots
umount /mnt

# 6. Mount subvolumes and restore
mount -o subvol=@rootfs,compress=zstd:3,noatime $ROOT_PARTITION /mnt
mkdir -p /mnt/{home,var,boot,boot/efi,.snapshots}
mount -o subvol=@home,compress=zstd:3,noatime $ROOT_PARTITION /mnt/home
mount -o subvol=@var,compress=zstd:3,noatime $ROOT_PARTITION /mnt/var
mount $BOOT_PARTITION /mnt/boot
mount $EFI_PARTITION /mnt/boot/efi

# 7. Restore system
echo "Restoring system to BTRFS..."
rsync -aAXv /mnt/backup/ /mnt/

# 8. Create @docker and @vms mount points
mkdir -p /mnt/var/lib/docker /mnt/var/lib/libvirt

# 9. Update fstab
BTRFS_UUID=$(blkid -s UUID -o value $ROOT_PARTITION)
cat > /mnt/etc/fstab << EOF
# /etc/fstab - BTRFS subvolume layout
# <device>                                <mount>    <type> <options>                                      <dump> <pass>

UUID=$BTRFS_UUID /              btrfs   ro,subvol=@rootfs,compress=zstd:3,noatime,space_cache=v2  0 0
UUID=$BTRFS_UUID /home          btrfs   rw,subvol=@home,compress=zstd:3,noatime,space_cache=v2    0 0
UUID=$BTRFS_UUID /var           btrfs   rw,subvol=@var,compress=zstd:3,noatime,space_cache=v2     0 0
UUID=$BTRFS_UUID /var/lib/docker btrfs  rw,subvol=@docker,compress=zstd:3,noatime,nodatacow       0 0
UUID=$BTRFS_UUID /var/lib/libvirt btrfs rw,subvol=@vms,compress=zstd:3,noatime,nodatacow          0 0
UUID=$BTRFS_UUID /.snapshots    btrfs   rw,subvol=@snapshots,compress=zstd:3,noatime              0 0

# Boot partitions (leave as-is)
UUID=$(blkid -s UUID -o value $BOOT_PARTITION) /boot ext4 defaults 0 2
UUID=$(blkid -s UUID -o value $EFI_PARTITION) /boot/efi vfat defaults 0 1
EOF

# 10. Remount root as read-only
mount -o remount,ro /mnt

# 11. Chroot and update bootloader
arch-chroot /mnt /bin/bash << 'CHROOT'
update-initramfs -u -k all
update-grub
CHROOT

# 12. Create initial backup snapshot
mount -o subvol=/,rw,compress=zstd:3 $ROOT_PARTITION /mnt/btrfs-root
btrfs subvolume snapshot /mnt/btrfs-root/@rootfs /mnt/btrfs-root/@rootfs-backup
umount /mnt/btrfs-root

echo "✓ Conversion complete! Reboot now."
echo "After reboot, verify with: mount | grep btrfs"
Phase 2: Post-Conversion Verification
bash#!/bin/bash
# verify-btrfs.sh - Verify BTRFS setup after reboot

echo "=== BTRFS Mount Verification ==="
mount | grep btrfs

echo -e "\n=== Subvolume List ==="
sudo btrfs subvolume list /

echo -e "\n=== Filesystem Usage ==="
sudo btrfs filesystem usage /

echo -e "\n=== Root filesystem should be READ-ONLY ==="
mount | grep "on / " | grep -q "ro," && echo "✓ Root is read-only" || echo "✗ Root is NOT read-only"

echo -e "\n=== Test read-only root ==="
touch /test-file 2>&1 | grep -q "Read-only" && echo "✓ Cannot write to root" || echo "✗ Can write to root (BAD)"

echo -e "\n=== Verify subvolume mounts ==="
for mount in / /home /var /var/lib/docker /var/lib/libvirt /.snapshots; do
    if mountpoint -q "$mount"; then
        echo "✓ $mount is mounted"
    else
        echo "✗ $mount is NOT mounted"
    fi
done

User & Permission Structure
User Creation Script
bash#!/bin/bash
# create-users.sh - Create all system users with proper groups

set -euo pipefail

echo "=== Creating User Structure ==="

# 1. Create service accounts (locked, no shell)
echo "Creating service accounts..."
sudo useradd -r -s /usr/sbin/nologin -c "Docker Administrator" docker-admin
sudo useradd -r -s /usr/sbin/nologin -c "VM Administrator" vm-admin

# 2. Create regular user: spooky
echo "Creating regular user: spooky"
sudo useradd -m -s /bin/bash -c "Regular User" spooky
sudo passwd spooky  # Set password interactively

# 3. Kang should already exist from initial install
# Add kang to necessary groups
echo "Configuring kang (admin user)..."
sudo usermod -aG sudo,kvm,libvirt,render,video kang

# 4. Configure spooky groups
echo "Configuring spooky (regular user)..."
sudo usermod -aG kvm,libvirt,render,video,audio spooky

# 5. Configure service account groups
sudo usermod -aG kvm,libvirt vm-admin
# docker-admin gets Docker access later via rootless setup

# 6. Enable lingering for service accounts (so systemd --user persists)
sudo loginctl enable-linger docker-admin
sudo loginctl enable-linger vm-admin
sudo loginctl enable-linger kang
sudo loginctl enable-linger spooky

echo "✓ Users created"
echo "  - kang: admin with sudo, rootless docker/kvm"
echo "  - spooky: regular user, limited docker/kvm, gaming"
echo "  - docker-admin: service account, full rootless docker"
echo "  - vm-admin: service account, full rootless kvm"
Group Permission Matrix
UserGroupsDocker AccessKVM AccessSudoPurposekangsudo, kvm, libvirt, render, videoFull rootlessFull rootlessYesSystem administrationspookykvm, libvirt, render, video, audioLimited rootlessLimited (polkit rules)NoDaily use, gamingdocker-admin(none initially)Full rootless (own daemon)NoNoDocker service managementvm-adminkvm, libvirtNoFull rootless (own session)NoVM service management

Rootless Docker Configuration
Installation & Setup
bash#!/bin/bash
# setup-rootless-docker.sh - Configure rootless Docker for all users

set -euo pipefail

echo "=== Installing Rootless Docker ==="

# 1. Remove system Docker if installed
sudo systemctl stop docker.service docker.socket || true
sudo apt remove -y docker.io docker-ce containerd || true

# 2. Install prerequisites
sudo apt install -y uidmap slirp4netns fuse-overlayfs dbus-user-session

# 3. Enable unprivileged port binding (ports < 1024)
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-rootless-docker.conf
sudo sysctl --system

# 4. Configure subuid/subgid ranges
echo "Configuring subordinate UID/GID ranges..."
for user in kang spooky docker-admin; do
    # Ensure user has subuid/subgid entries
    if ! grep -q "^${user}:" /etc/subuid; then
        echo "${user}:100000:65536" | sudo tee -a /etc/subuid
    fi
    if ! grep -q "^${user}:" /etc/subgid; then
        echo "${user}:100000:65536" | sudo tee -a /etc/subgid
    fi
done

# 5. Install rootless Docker for each user
install_rootless_for_user() {
    local user=$1
    echo "Installing rootless Docker for: $user"
    
    sudo -u $user bash << 'USERSCRIPT'
    set -euo pipefail
    
    # Download and install rootless Docker
    cd ~
    curl -fsSL https://get.docker.com/rootless | sh
    
    # Add to PATH in .bashrc
    if ! grep -q 'docker/bin' ~/.bashrc; then
        cat >> ~/.bashrc << 'EOF'

# Rootless Docker
export PATH="$HOME/bin:$PATH"
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
EOF
    fi
    
    # Enable Docker service
    systemctl --user enable docker.service
    systemctl --user start docker.service
    
    # Verify installation
    export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
    ~/bin/docker version
USERSCRIPT
    
    echo "✓ Rootless Docker installed for $user"
}

# Install for each user
for user in kang docker-admin spooky; do
    install_rootless_for_user $user
done

echo "=== Rootless Docker Installation Complete ==="
Docker Networking Configuration
bash#!/bin/bash
# configure-docker-networks.sh - Set up Docker networks for LAN access

set -euo pipefail

# Run as docker-admin user for centralized network management
sudo -u docker-admin bash << 'DOCKER_ADMIN_SCRIPT'
set -euo pipefail

export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock

echo "=== Configuring Docker Networks ==="

# 1. Default bridge (rootless-isolated)
echo "Creating default bridge network..."
~/bin/docker network create \
    --driver bridge \
    --subnet 172.20.0.0/16 \
    --gateway 172.20.0.1 \
    rootless-bridge || echo "Network already exists"

# 2. LAN-accessible network (macvlan)
# NOTE: Requires host network interface (e.g., eth0 or enp0s3)
HOST_INTERFACE="eth0"  # ADJUST THIS

echo "Creating LAN-accessible macvlan network..."
~/bin/docker network create \
    --driver macvlan \
    --subnet 192.168.1.0/24 \
    --gateway 192.168.1.1 \
    --ip-range 192.168.1.192/27 \
    -o parent=$HOST_INTERFACE \
    lan-network || echo "Network already exists"

# 3. Internal-only network (for container-to-container)
echo "Creating internal-only network..."
~/bin/docker network create \
    --driver bridge \
    --internal \
    internal-network || echo "Network already exists"

echo "✓ Docker networks configured"
~/bin/docker network ls
DOCKER_ADMIN_SCRIPT
Permission Limiting for Spooky
bash#!/bin/bash
# limit-docker-spooky.sh - Restrict spooky's Docker access

# Strategy: Use Docker contexts with socket proxies
# spooky connects to docker-admin's socket via proxy with ACLs

cat > /tmp/docker-proxy-spooky.service << 'EOF'
[Unit]
Description=Docker Socket Proxy for Spooky
After=network.target

[Service]
Type=simple
User=docker-admin
ExecStart=/usr/bin/socat \
    UNIX-LISTEN:/run/user/1001/docker-spooky.sock,fork,mode=660,user=spooky \
    UNIX-CONNECT:/run/user/1002/docker.sock
Restart=always

[Install]
WantedBy=default.target
EOF

# Install as docker-admin user service
sudo cp /tmp/docker-proxy-spooky.service /home/docker-admin/.config/systemd/user/
sudo -u docker-admin systemctl --user daemon-reload
sudo -u docker-admin systemctl --user enable --now docker-proxy-spooky.service

# Configure spooky's Docker context
sudo -u spooky bash << 'SPOOKY_SCRIPT'
mkdir -p ~/.docker
cat > ~/.docker/config.json << 'EOF'
{
  "currentContext": "limited",
  "contexts": {
    "limited": {
      "description": "Limited Docker access via proxy",
      "docker": {
        "host": "unix:///run/user/1001/docker-spooky.sock"
      }
    }
  }
}
EOF
SPOOKY_SCRIPT

echo "✓ Spooky's Docker access limited to proxy socket"
Docker Compose Access
bash#!/bin/bash
# setup-docker-compose.sh - Install Docker Compose V2

# Install for all Docker users
for user in kang docker-admin spooky; do
    echo "Installing Docker Compose for: $user"
    sudo -u $user bash << 'COMPOSE_INSTALL'
    set -euo pipefail
    
    mkdir -p ~/.docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
        -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
    
    # Verify
    export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
    ~/bin/docker compose version
COMPOSE_INSTALL
done

echo "✓ Docker Compose installed for all users"

Rootless KVM/QEMU Configuration
System-Level Setup
bash#!/bin/bash
# setup-kvm-base.sh - Configure KVM/QEMU system components

set -euo pipefail

echo "=== Installing KVM/QEMU Components ==="

# 1. Install packages
sudo apt install -y \
    qemu-system-x86 \
    qemu-utils \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    libvirt-daemon \
    virt-manager \
    ovmf \
    bridge-utils \
    dnsmasq

# 2. Verify virtualization support
if ! grep -E '(vmx|svm)' /proc/cpuinfo > /dev/null; then
    echo "✗ ERROR: CPU virtualization not supported or not enabled in BIOS"
    exit 1
fi
echo "✓ CPU virtualization supported"

# 3. Load KVM modules
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd
echo "✓ KVM modules loaded"

# 4. Configure libvirt for user sessions
sudo systemctl enable libvirtd.service
sudo systemctl start libvirtd.service

# Enable user session virtqemud socket for each user
for user in kang spooky vm-admin; do
    echo "Configuring libvirt for: $user"
    sudo -u $user systemctl --user enable virtqemud.socket
    sudo -u $user systemctl --user start virtqemud.socket
done

echo "✓ Libvirt configured for user sessions"
Per-User VM Setup
bash#!/bin/bash
# setup-user-vms.sh - Configure per-user VM environments

setup_user_libvirt() {
    local user=$1
    echo "=== Setting up libvirt for: $user ==="
    
    sudo -u $user bash << 'USER_LIBVIRT'
    set -euo pipefail
    
    # 1. Create user-specific storage pool
    mkdir -p ~/.local/share/libvirt/images
    
    # Define storage pool
    virsh -c qemu:///session pool-define-as default \
        dir --target "$HOME/.local/share/libvirt/images" || true
    virsh -c qemu:///session pool-start default || true
    virsh -c qemu:///session pool-autostart default
    
    # 2. Create user-specific network (NAT)
    cat > /tmp/user-network.xml << 'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
    
    virsh -c qemu:///session net-define /tmp/user-network.xml || true
    virsh -c qemu:///session net-start default || true
    virsh -c qemu:///session net-autostart default
    rm /tmp/user-network.xml
    
    echo "✓ Libvirt configured for $USER"
USER_LIBVIRT
}

# Setup for each user
for user in kang vm-admin; do
    setup_user_libvirt $user
done

echo "=== User VM environments ready ==="
Polkit Rules for Limited Access (Spooky)
bash#!/bin/bash
# configure-polkit-libvirt.sh - Restrict spooky's VM permissions

cat | sudo tee /etc/polkit-1/rules.d/50-libvirt-spooky.rules << 'EOF'
// Allow spooky to manage VMs in their session, but not create/delete
polkit.addRule(function(action, subject) {
    if (subject.user == "spooky") {
        // Allow: Start, stop, reboot VMs
        if (action.id == "org.libvirt.unix.manage" ||
            action.id == "org.libvirt.api.domain.start" ||
            action.id == "org.libvirt.api.domain.stop" ||
            action.id == "org.libvirt.api.domain.reboot" ||
            action.id == "org.libvirt.api.domain.save" ||
            action.id == "org.libvirt.api.domain.suspend") {
            return polkit.Result.YES;
        }
        
        // Deny: Create, delete, modify VMs
        if (action.id == "org.libvirt.api.domain.create" ||
            action.id == "org.libvirt.api.domain.undefine" ||
            action.id == "org.libvirt.api.network.create" ||
            action.id == "org.libvirt.api.network.destroy") {
            return polkit.Result.NO;
        }
        
        // Allow read-only operations
        if (action.id.indexOf("org.libvirt.api.domain.read") == 0 ||
            action.id.indexOf("org.libvirt.api.network.read") == 0) {
            return polkit.Result.YES;
        }
    }
});

// vm-admin and kang have full access to their user sessions
polkit.addRule(function(action, subject) {
    if (subject.user == "vm-admin" || subject.user == "kang") {
        if (action.id.indexOf("org.libvirt") == 0) {
            return polkit.Result.YES;
        }
    }
});
EOF

sudo systemctl restart polkit

echo "✓ Polkit rules configured for libvirt"

GPU Passthrough Setup
IOMMU & VFIO Configuration
bash#!/bin/bash
# setup-gpu-passthrough.sh - Configure GPU passthrough for VMs

set -euo pipefail

echo "=== Configuring GPU Passthrough ==="

# 1. Verify IOMMU support
if ! dmesg | grep -e "IOMMU enabled"; then
    echo "✗ IOMMU not enabled. Check BIOS settings."
    exit 1
fi
echo "✓ IOMMU enabled"

# 2. Identify GPU PCI IDs
echo "Detecting GPU..."
GPU_IDS=$(lspci -nn | grep -i vga | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}')
GPU_AUDIO_IDS=$(lspci -nn | grep -i audio | grep -i nvidia | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}')

echo "GPU Device IDs: $GPU_IDS"
echo "GPU Audio IDs: $GPU_AUDIO_IDS"

# Combine IDs
VFIO_IDS="${GPU_IDS},${GPU_AUDIO_IDS}"

# 3. Configure VFIO early loading
cat | sudo tee /etc/modprobe.d/vfio.conf << EOF
# Bind GPU to VFIO at boot
options vfio-pci ids=$VFIO_IDS
options vfio-pci disable_vga=1

# Prevent host drivers from claiming GPU
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
softdep amdgpu pre: vfio-pci
softdep radeon pre: vfio-pci
EOF

# 4. Blacklist GPU drivers on host
cat | sudo tee /etc/modprobe.d/blacklist-gpu.conf << EOF
# Blacklist GPU drivers for passthrough
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist amdgpu
blacklist radeon
EOF

# 5. Update GRUB for IOMMU
GRUB_CMDLINE="intelTurn on web search in Search and tools menu. Otherwise, links provided may not be accurate or up to date.Continue12:41 PM_iommu=on iommu=pt vfio-pci.ids=$VFIO_IDS"
If AMD CPU, use: amd_iommu=on iommu=pt vfio-pci.ids=$VFIO_IDS
sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE /" /etc/default/grub
sudo update-grub
6. Add VFIO modules to initramfs
cat | sudo tee /etc/initramfs-tools/modules << EOF
VFIO modules for GPU passthrough
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
sudo update-initramfs -u -k all
7. Verify IOMMU groups
echo "=== IOMMU Groups ==="
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n={d#*/iommu_groups/*}; n=
{n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done | sort -V

echo ""
echo "✓ GPU passthrough configured"
echo "⚠️  REBOOT REQUIRED for changes to take effect"
echo ""
echo "After reboot, verify with:"
echo "  lspci -nnk | grep -A 3 VGA"
echo "  dmesg | grep -i vfio"

### VM XML Template for GPU Passthrough
```bash
#!/bin/bash
# create-gpu-vm-template.sh - Create VM template with GPU passthrough

cat > /tmp/windows-gpu-vm.xml << 'EOF'
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>windows-gaming</name>
  <memory unit='GiB'>16</memory>
  <currentMemory unit='GiB'>16</currentMemory>
  <vcpu placement='static'>8</vcpu>
  
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>/usr/share/OVMF/OVMF_CODE.fd</loader>
    <nvram>/var/lib/libvirt/qemu/nvram/windows-gaming_VARS.fd</nvram>
    <boot dev='hd'/>
  </os>
  
  <features>
    <acpi/>
    <apic/>
    <hyperv>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vendor_id state='on' value='1234567890ab'/>
    </hyperv>
    <kvm>
      <hidden state='on'/>
    </kvm>
    <vmport state='off'/>
  </features>
  
  <cpu mode='host-passthrough' check='none' migratable='on'>
    <topology sockets='1' dies='1' cores='4' threads='2'/>
    <feature policy='require' name='topoext'/>
  </cpu>
  
  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
    <timer name='hypervclock' present='yes'/>
  </clock>
  
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    
    <!-- Main disk -->
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='writeback' io='threads'/>
      <source file='/var/lib/libvirt/images/windows-gaming.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    
    <!-- GPU passthrough (ADJUST PCI ADDRESS) -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </hostdev>
    
    <!-- GPU Audio passthrough (ADJUST PCI ADDRESS) -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </hostdev>
    
    <!-- Network -->
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    
    <!-- USB Controller for passthrough -->
    <controller type='usb' model='qemu-xhci' ports='15'/>
    
    <!-- Input devices -->
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    
    <!-- Graphics (for initial setup, remove after GPU drivers installed) -->
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1'/>
    </video>
  </devices>
  
  <qemu:commandline>
    <qemu:arg value='-cpu'/>
    <qemu:arg value='host,hv_time,kvm=off,hv_vendor_id=null'/>
  </qemu:commandline>
</domain>
EOF

echo "✓ VM template created: /tmp/windows-gpu-vm.xml"
echo ""
echo "To create the VM:"
echo "  1. Get GPU PCI address: lspci | grep VGA"
echo "  2. Edit /tmp/windows-gpu-vm.xml and update <hostdev> addresses"
echo "  3. Create disk: qemu-img create -f qcow2 /var/lib/libvirt/images/windows-gaming.qcow2 100G"
echo "  4. Define VM: virsh -c qemu:///session define /tmp/windows-gpu-vm.xml"
echo "  5. Install Windows with ISO attached"
```

### Network-Accessible GPU VMs
```bash
#!/bin/bash
# configure-vm-network-access.sh - Allow LAN access to GPU VMs

cat > /tmp/vm-bridge-network.xml << 'EOF'
<network>
  <name>lan-bridge</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

# Create bridge on host (requires netplan or /etc/network/interfaces config)
cat | sudo tee /etc/network/interfaces.d/br0 << 'EOF'
# Bridge for VM LAN access
auto br0
iface br0 inet dhcp
    bridge_ports eth0
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0
EOF

# Apply network config
sudo systemctl restart networking

# Define libvirt network
virsh -c qemu:///session net-define /tmp/vm-bridge-network.xml
virsh -c qemu:///session net-start lan-bridge
virsh -c qemu:///session net-autostart lan-bridge

echo "✓ VMs can now access LAN via 'lan-bridge' network"
echo "  Update VM XML: <interface type='network'><source network='lan-bridge'/></interface>"
```

---

## Network Configuration

### Host Network Setup
```bash
#!/bin/bash
# configure-host-network.sh - Setup host networking for containers and VMs

set -euo pipefail

echo "=== Configuring Host Networking ==="

# 1. Enable IP forwarding
cat | sudo tee /etc/sysctl.d/99-forwarding.conf << 'EOF'
# Enable IP forwarding for containers and VMs
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Rootless networking
net.ipv4.ip_unprivileged_port_start = 80
EOF

sudo sysctl --system

# 2. Configure firewall (UFW)
sudo apt install -y ufw

# Allow SSH
sudo ufw allow 22/tcp

# Allow Docker services (adjust ports as needed)
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 8080/tcp  # Common Docker service port

# Allow libvirt bridge
sudo ufw allow in on virbr0
sudo ufw allow out on virbr0

# Enable firewall
sudo ufw --force enable

echo "✓ Host networking configured"
```

### Docker LAN Service Exposure
```bash
#!/bin/bash
# expose-docker-service.sh - Example: Expose nginx on LAN

# Run as docker-admin
sudo -u docker-admin bash << 'DOCKER_SCRIPT'
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock

# Example: Nginx web server accessible on LAN
~/bin/docker run -d \
  --name nginx-web \
  --network lan-network \
  --ip 192.168.1.200 \
  -v ~/www:/usr/share/nginx/html:ro \
  nginx:latest

echo "✓ Nginx running at http://192.168.1.200"
DOCKER_SCRIPT
```

### VM LAN Access Configuration
```bash
#!/bin/bash
# configure-vm-lan-access.sh - Setup VM for LAN accessibility

# Example: Attach Windows GPU VM to bridge network
virsh -c qemu:///session dumpxml windows-gaming > /tmp/vm-config.xml

# Edit XML to add bridge interface
# Then redefine:
# virsh -c qemu:///session define /tmp/vm-config.xml

echo "VM 'windows-gaming' will be accessible on LAN after reboot"
echo "Configure static IP in Windows or use DHCP reservation"
```

---

## Immutable Root Management

### Update System Script
```bash
#!/bin/bash
# system-update.sh - Update immutable root filesystem

set -euo pipefail

echo "=== Immutable Root Update Process ==="

# Must run as sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)" 
   exit 1
fi

BTRFS_ROOT="/dev/sda3"  # ADJUST THIS

# 1. Backup current root
echo "Creating backup of current root..."
mount -o subvol=/,rw $BTRFS_ROOT /mnt
btrfs subvolume snapshot /mnt/@rootfs /mnt/@rootfs-backup
umount /mnt

# 2. Create writable snapshot for updates
echo "Creating writable update snapshot..."
mount -o subvol=/,rw $BTRFS_ROOT /mnt
btrfs subvolume snapshot /mnt/@rootfs /mnt/@rootfs-update
umount /mnt

# 3. Mount update snapshot
echo "Mounting update snapshot..."
mkdir -p /mnt/update
mount -o subvol=@rootfs-update,rw,compress=zstd:3 $BTRFS_ROOT /mnt/update

# Mount necessary filesystems for chroot
mount -o bind /dev /mnt/update/dev
mount -o bind /proc /mnt/update/proc
mount -o bind /sys /mnt/update/sys
mount -o bind /run /mnt/update/run

# 4. Chroot and perform updates
echo "Entering chroot environment..."
echo "Run your updates (apt update && apt upgrade, etc.)"
echo "Type 'exit' when done."
chroot /mnt/update /bin/bash

# 5. Cleanup mounts
echo "Cleaning up..."
umount /mnt/update/run
umount /mnt/update/sys
umount /mnt/update/proc
umount /mnt/update/dev
umount /mnt/update

# 6. Swap snapshots
echo "Swapping to updated snapshot..."
mount -o subvol=/,rw $BTRFS_ROOT /mnt

# Remove old root
btrfs subvolume delete /mnt/@rootfs

# Promote update to new root
mv /mnt/@rootfs-update /mnt/@rootfs

umount /mnt

echo "✓ Update complete!"
echo "⚠️  REBOOT to use updated system"
echo ""
echo "To rollback if issues occur:"
echo "  sudo btrfs subvolume delete /@rootfs"
echo "  sudo btrfs subvolume snapshot /@rootfs-backup /@rootfs"
echo "  sudo reboot"
```

### Rollback Script
```bash
#!/bin/bash
# system-rollback.sh - Rollback to previous snapshot

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)" 
   exit 1
fi

BTRFS_ROOT="/dev/sda3"  # ADJUST THIS

echo "=== Rolling Back to Previous Snapshot ==="

# Confirm
read -p "This will rollback to @rootfs-backup. Continue? (yes/no): " confirm
[[ "$confirm" != "yes" ]] && exit 1

# 1. Mount BTRFS root
mount -o subvol=/,rw $BTRFS_ROOT /mnt

# 2. Check if backup exists
if ! btrfs subvolume list /mnt | grep -q "@rootfs-backup"; then
    echo "✗ No backup snapshot found!"
    umount /mnt
    exit 1
fi

# 3. Swap snapshots
echo "Swapping snapshots..."
btrfs subvolume delete /mnt/@rootfs
btrfs subvolume snapshot /mnt/@rootfs-backup /mnt/@rootfs

umount /mnt

echo "✓ Rollback complete!"
echo "⚠️  REBOOT to use rolled-back system"
```

### Automated Snapshot Management
```bash
#!/bin/bash
# snapshot-manager.sh - Automated BTRFS snapshot management

set -euo pipefail

BTRFS_ROOT="/dev/sda3"  # ADJUST THIS
SNAPSHOT_DIR="/.snapshots"
MAX_SNAPSHOTS=7  # Keep last 7 snapshots

# Create snapshot with timestamp
create_snapshot() {
    local subvol=$1
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_name="${subvol}-${timestamp}"
    
    echo "Creating snapshot: $snapshot_name"
    btrfs subvolume snapshot "$subvol" "$SNAPSHOT_DIR/$snapshot_name"
}

# Cleanup old snapshots
cleanup_snapshots() {
    local subvol=$1
    local snapshots=($(ls -1 "$SNAPSHOT_DIR" | grep "^${subvol}-" | sort -r))
    local count=${#snapshots[@]}
    
    if [[ $count -gt $MAX_SNAPSHOTS ]]; then
        echo "Cleaning up old snapshots (keeping $MAX_SNAPSHOTS)..."
        for ((i=$MAX_SNAPSHOTS; i<$count; i++)); do
            echo "Deleting: ${snapshots[$i]}"
            btrfs subvolume delete "$SNAPSHOT_DIR/${snapshots[$i]}"
        done
    fi
}

# Main
mkdir -p "$SNAPSHOT_DIR"

# Snapshot home (daily)
create_snapshot "/home"
cleanup_snapshots "@home"

# Snapshot var (weekly - adjust as needed)
if [[ $(date +%u) -eq 1 ]]; then  # Monday
    create_snapshot "/var"
    cleanup_snapshots "@var"
fi

echo "✓ Snapshot management complete"
```

### Systemd Timer for Automatic Snapshots
```bash
#!/bin/bash
# setup-snapshot-timer.sh - Configure automatic snapshots

# Create systemd service
cat | sudo tee /etc/systemd/system/btrfs-snapshot.service << 'EOF'
[Unit]
Description=BTRFS Automatic Snapshots
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/snapshot-manager.sh
EOF

# Create systemd timer
cat | sudo tee /etc/systemd/system/btrfs-snapshot.timer << 'EOF'
[Unit]
Description=BTRFS Snapshot Timer
Requires=btrfs-snapshot.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Install snapshot script
sudo cp snapshot-manager.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/snapshot-manager.sh

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable btrfs-snapshot.timer
sudo systemctl start btrfs-snapshot.timer

echo "✓ Automatic snapshots configured (daily)"
echo "Check status: systemctl status btrfs-snapshot.timer"
```

---

## Maintenance & Operations

### Daily Operations

**Starting Services**
```bash
# Check Docker status (per user)
systemctl --user status docker

# Check VM status
virsh -c qemu:///session list --all

# Start a VM
virsh -c qemu:///session start windows-gaming

# Start Docker container
docker start nginx-web
```

**Monitoring**
```bash
# Check filesystem usage
sudo btrfs filesystem usage /

# Check subvolume status
sudo btrfs subvolume list /

# Check snapshots
ls -lh /.snapshots/

# Docker resource usage
docker stats

# VM resource usage
virsh -c qemu:///session domstats windows-gaming
```

### System Updates

**Regular Updates (Non-Breaking)**
```bash
# As kang user
sudo /usr/local/bin/system-update.sh

# In chroot:
apt update
apt upgrade -y
apt autoremove -y

# Exit chroot
exit

# Reboot
sudo reboot
```

**Major Updates (Debian Version Upgrades)**
```bash
# Same process, but edit /etc/apt/sources.list in chroot
# Change debian version (e.g., bookworm -> trixie)
# Then apt update && apt full-upgrade
```

### Backup Strategy

**Critical Data Locations**
/home                    - User data (daily snapshots + external backup)
/var/lib/docker          - Container data (selective backup)
/var/lib/libvirt/images  - VM images (selective backup)
/.snapshots              - BTRFS snapshots (keep on same disk)
@rootfs-backup           - Last known-good root (keep on same disk)

**Backup Script Example**
```bash
#!/bin/bash
# backup-critical-data.sh - Backup user data to external drive

BACKUP_DEST="/mnt/external-backup"
TIMESTAMP=$(date +%Y%m%d)

# Backup home directories
rsync -aAXv --delete \
    /home/ \
    "$BACKUP_DEST/home-$TIMESTAMP/"

# Backup Docker volumes (selective)
rsync -aAXv \
    /var/lib/docker/volumes/ \
    "$BACKUP_DEST/docker-volumes-$TIMESTAMP/"

# Backup VM images (selective)
rsync -aAXv \
    /var/lib/libvirt/images/*.qcow2 \
    "$BACKUP_DEST/vm-images-$TIMESTAMP/"

echo "✓ Backup complete: $BACKUP_DEST"
```

### Performance Optimization

**BTRFS Maintenance**
```bash
# Balance filesystem (monthly)
sudo btrfs balance start -dusage=50 /

# Scrub for errors (monthly)
sudo btrfs scrub start /
sudo btrfs scrub status /

# Defragment (if needed, but rarely necessary with zstd)
sudo btrfs filesystem defragment -r -czstd /home
```

**Docker Optimization**
```bash
# Prune unused resources
docker system prune -af --volumes

# Check disk usage
docker system df
```

**VM Optimization**
```bash
# Convert VM disk to qcow2 with compression
qemu-img convert -O qcow2 -c input.qcow2 output-compressed.qcow2

# Reclaim unused space
virsh -c qemu:///session domblklist windows-gaming
virt-sparsify --in-place /path/to/disk.qcow2
```

---

## Troubleshooting

### Common Issues

**Issue: Root filesystem became writable**
```bash
# Remount as read-only
sudo mount -o remount,ro /

# Verify
mount | grep "on / "

# If persists, check fstab
grep "/ " /etc/fstab
```

**Issue: Docker won't start (rootless)**
```bash
# Check user service
systemctl --user status docker

# Check journal
journalctl --user -u docker -n 50

# Verify subuid/subgid
grep $USER /etc/subuid /etc/subgid

# Reinstall rootless Docker
~/bin/dockerd-rootless-setuptool.sh uninstall
curl -fsSL https://get.docker.com/rootless | sh
```

**Issue: VM won't start with GPU**
```bash
# Check VFIO binding
lspci -nnk | grep -A 3 VGA

# Should show: Kernel driver in use: vfio-pci

# If not, rebuild initramfs
sudo update-initramfs -u -k all
sudo reboot

# Check IOMMU groups
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done
```

**Issue: Can't write to /var or /home**
```bash
# Check mount options
mount | grep -E "(/var|/home)"

# Should show rw, not ro

# Remount if needed
sudo mount -o remount,rw /var
sudo mount -o remount,rw /home
```

**Issue: Out of space**
```bash
# Check BTRFS usage
sudo btrfs filesystem usage /

# Delete old snapshots
sudo btrfs subvolume list /.snapshots
sudo btrfs subvolume delete /.snapshots/@home-20231201-*

# Balance to reclaim space
sudo btrfs balance start -dusage=5 /
```

**Issue: Docker network not accessible on LAN**
```bash
# Check macvlan network
docker network inspect lan-network

# Verify host interface
ip link show

# Check firewall
sudo ufw status

# Test connectivity from container
docker run --rm --network lan-network alpine ping 192.168.1.1
```

### Emergency Recovery

**Boot into read-write root (emergency)**
```bash
# At GRUB, edit boot entry (press 'e')
# Find line starting with 'linux'
# Change 'ro' to 'rw'
# Press Ctrl+X to boot

# After fixing issues, reboot normally
```

**Complete system rollback from live USB**
```bash
# Boot Debian Live USB
# Mount BTRFS root
sudo mkdir /mnt/btrfs
sudo mount /dev/sda3 /mnt/btrfs

# List snapshots
sudo btrfs subvolume list /mnt/btrfs

# Delete current root
sudo btrfs subvolume delete /mnt/btrfs/@rootfs

# Restore from backup
sudo btrfs subvolume snapshot /mnt/btrfs/@rootfs-backup /mnt/btrfs/@rootfs

# Unmount and reboot
sudo umount /mnt/btrfs
sudo reboot
```

---

## Summary Checklist

### Initial Setup
- [ ] Backup all data
- [ ] Convert to BTRFS with subvolumes
- [ ] Verify read-only root mount
- [ ] Create users (kang, spooky, docker-admin, vm-admin)
- [ ] Install rootless Docker for all users
- [ ] Configure Docker networking (bridge, macvlan)
- [ ] Install KVM/QEMU components
- [ ] Configure per-user libvirt sessions
- [ ] Setup polkit rules for limited access
- [ ] Configure GPU passthrough (VFIO)
- [ ] Test VM with GPU passthrough
- [ ] Setup automatic snapshots
- [ ] Configure firewall rules
- [ ] Create backup strategy

### Verification
- [ ] Root filesystem is read-only
- [ ] All subvolumes mounted correctly
- [ ] Docker containers can start (rootless)
- [ ] Docker services accessible on LAN
- [ ] VMs can start and access GPU
- [ ] VMs accessible on LAN
- [ ] Snapshots working automatically
- [ ] System update process works
- [ ] Rollback process works
- [ ] Regular user (spooky) has limited permissions
- [ ] Service accounts (docker-admin, vm-admin) functional

### Ongoing Maintenance
- [ ] Weekly: Check snapshot usage
- [ ] Monthly: BTRFS balance and scrub
- [ ] Monthly: Prune Docker resources
- [ ] Quarterly: Test rollback procedure
- [ ] As needed: Update system via snapshot method
- [ ] As needed: Backup critical data to external drive

---

## Quick Reference Commands
```bash
# System Updates
sudo /usr/local/bin/system-update.sh

# Rollback
sudo /usr/local/bin/system-rollback.sh

# Docker (rootless)
docker ps                    # List containers
docker compose up -d         # Start compose stack
systemctl --user status docker  # Check Docker service

# VMs
virsh -c qemu:///session list --all     # List VMs
virsh -c qemu:///session start VM_NAME  # Start VM
virt-manager                            # GUI management

# Snapshots
sudo btrfs subvolume list /             # List all subvolumes
ls -lh /.snapshots/                     # View snapshots
sudo /usr/local/bin/snapshot-manager.sh # Manual snapshot

# Filesystem
sudo btrfs filesystem usage /           # Disk usage
sudo btrfs balance start -dusage=50 /   # Balance
sudo btrfs scrub start /                # Integrity check

# Monitoring
htop                         # System resources
docker stats                 # Container resources
virsh -c qemu:///session domstats VM_NAME  # VM resources
```

---

This comprehensive guide provides a complete, production-ready immutable Debian system with rootless Docker/KVM, GPU passthrough, and tight permission scoping. All scripts are modular and can be run independently or as a complete setup workflow.