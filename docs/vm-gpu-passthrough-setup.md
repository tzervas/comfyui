# GPU Passthrough VM Setup for akula-prime

## Overview
This guide covers setting up a hardened VM with GPU passthrough on akula-prime, allowing the host to use iGPU while the VM gets dedicated GPU access for containerized AI workloads.

## Prerequisites

### Hardware Requirements
- CPU with IOMMU support (Intel VT-d or AMD-Vi)
- Integrated GPU (iGPU) for host display
- Dedicated GPU (dGPU) for VM passthrough
- GPUs in separate IOMMU groups

### Software Requirements
- KVM/QEMU
- libvirt
- virt-manager (optional, for GUI management)
- NVIDIA/AMD GPU drivers

## BIOS Configuration

1. **Enable IOMMU:**
   - Intel: VT-d
   - AMD: AMD-Vi / IOMMU

2. **Set Primary Display:**
   - Set iGPU as primary display adapter
   - Or configure for dynamic switching

3. **Above 4G Decoding:**
   - Enable if available (required for some GPUs)

4. **Resizable BAR:**
   - Enable if supported by GPU

## Host System Setup

### 1. Enable IOMMU in Kernel

Edit `/etc/default/grub`:
```bash
# For Intel CPUs
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"

# For AMD CPUs
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

Update GRUB:
```bash
sudo update-grub
sudo reboot
```

### 2. Verify IOMMU Groups

```bash
#!/bin/bash
# check-iommu-groups.sh
shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```

GPU should be in its own IOMMU group or with only its audio device.

### 3. Identify GPU PCI IDs

```bash
lspci -nn | grep -i nvidia
# Example output:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA102 [GeForce RTX 3090] [10de:2204] (rev a1)
# 01:00.1 Audio device [0403]: NVIDIA Corporation GA102 High Definition Audio Controller [10de:1aef] (rev a1)
```

Note the PCI IDs (e.g., `10de:2204` and `10de:1aef`).

### 4. Bind GPU to VFIO

Create `/etc/modprobe.d/vfio.conf`:
```bash
options vfio-pci ids=10de:2204,10de:1aef
```

Create `/etc/modprobe.d/blacklist-nvidia.conf`:
```bash
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
```

Update initramfs:
```bash
sudo update-initramfs -u
sudo reboot
```

### 5. Verify VFIO Binding

```bash
lspci -nnk -d 10de:2204
# Should show:
# Kernel driver in use: vfio-pci
```

## VM Creation

### 1. Install Required Packages

```bash
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf
sudo usermod -aG libvirt,kvm $USER
```

### 2. Create VM with virt-manager

1. **Basic Configuration:**
   - Name: `gpu-worker-vm`
   - OS: Debian/Ubuntu
   - Memory: 16GB
   - CPUs: 8 cores
   - Disk: 100GB

2. **Before Install:**
   - Change firmware to UEFI (OVMF)
   - Add GPU via "Add Hardware" > "PCI Host Device"
   - Select GPU and audio device

3. **Network:**
   - Bridge or NAT (bridge recommended)
   - Static IP: 192.168.1.99

### 3. Manual libvirt XML Configuration

Example GPU passthrough section in VM XML:
```xml
<domain type='kvm'>
  <name>gpu-worker-vm</name>
  <memory unit='KiB'>16777216</memory>
  <vcpu placement='static'>8</vcpu>
  
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
  </features>

  <cpu mode='host-passthrough'>
    <topology sockets='1' cores='8' threads='1'/>
  </cpu>

  <devices>
    <!-- GPU -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </hostdev>
    
    <!-- GPU Audio -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
      </source>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x1'/>
    </hostdev>
  </devices>
</domain>
```

## VM Operating System Setup

### 1. Install OS in VM

Install Debian or Ubuntu with minimal packages.

### 2. Install NVIDIA Drivers in VM

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install kernel headers
sudo apt install linux-headers-$(uname -r)

# Install NVIDIA drivers
sudo apt install nvidia-driver nvidia-cuda-toolkit

# Reboot
sudo reboot
```

Verify GPU:
```bash
nvidia-smi
```

### 3. Install Docker in VM

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update
sudo apt install nvidia-docker2
sudo systemctl restart docker
```

Verify GPU in Docker:
```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### 4. Deploy GPU Worker Stack in VM

```bash
# Clone or copy project
git clone <repo> /opt/comfyui
cd /opt/comfyui

# Create .env.desktop with required variables
cp .env.desktop.example .env.desktop
# Edit with your values

# Deploy stack
./tools/deploy-gpu-worker.sh
```

## Host Display Management

### Option 1: Static iGPU Configuration
Set iGPU as primary in BIOS. Host always uses iGPU.

**Pros:**
- Simple, no switching needed
- Stable

**Cons:**
- Can't use dGPU on host when VM is off

### Option 2: Dynamic Switching

Create switching scripts:

**Switch to VM mode (unbind dGPU):**
```bash
#!/bin/bash
# switch-to-vm.sh

# Stop display manager
sudo systemctl stop gdm3

# Unbind GPU from nvidia driver
echo "0000:01:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/unbind
echo "0000:01:00.1" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/unbind

# Bind to vfio-pci
echo "10de 2204" | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
echo "10de 1aef" | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id

# Start VM
virsh start gpu-worker-vm

# Restart display manager (using iGPU)
sudo systemctl start gdm3
```

**Switch to host mode (bind dGPU):**
```bash
#!/bin/bash
# switch-to-host.sh

# Stop VM
virsh shutdown gpu-worker-vm

# Wait for VM to stop
sleep 10

# Stop display manager
sudo systemctl stop gdm3

# Unbind from vfio-pci
echo "0000:01:00.0" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind
echo "0000:01:00.1" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind

# Remove from vfio-pci
echo "10de 2204" | sudo tee /sys/bus/pci/drivers/vfio-pci/remove_id
echo "10de 1aef" | sudo tee /sys/bus/pci/drivers/vfio-pci/remove_id

# Bind to nvidia driver
echo "0000:01:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/bind
echo "0000:01:00.1" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/bind

# Reload nvidia modules
sudo modprobe nvidia

# Restart display manager (using dGPU)
sudo systemctl start gdm3
```

### Option 3: Looking Glass
Use Looking Glass for low-latency VM display pass through to host:
- VM renders to shared memory
- Host application displays VM output
- No physical display switching needed

## VM Networking

### Bridge Configuration for Direct LAN Access

Create bridge in `/etc/network/interfaces`:
```bash
auto br0
iface br0 inet static
    address 192.168.1.170
    netmask 255.255.255.0
    gateway 192.168.1.1
    bridge_ports enp3s0
    bridge_stp off
    bridge_fd 0
```

VM network XML:
```xml
<interface type='bridge'>
  <source bridge='br0'/>
  <model type='virtio'/>
</interface>
```

VM static IP in VM's `/etc/network/interfaces`:
```bash
auto ens3
iface ens3 inet static
    address 192.168.1.99
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1
```

## VM Management

### Start VM
```bash
virsh start gpu-worker-vm
```

### Stop VM
```bash
virsh shutdown gpu-worker-vm
```

### Auto-start on Host Boot
```bash
virsh autostart gpu-worker-vm
```

### Console Access
```bash
virsh console gpu-worker-vm
```

### Resource Monitoring
```bash
virt-top
```

## Performance Tuning

### CPU Pinning
Pin VM vCPUs to physical cores:
```xml
<vcpu placement='static'>8</vcpu>
<cputune>
  <vcpupin vcpu='0' cpuset='2'/>
  <vcpupin vcpu='1' cpuset='3'/>
  <vcpupin vcpu='2' cpuset='4'/>
  <vcpupin vcpu='3' cpuset='5'/>
  <vcpupin vcpu='4' cpuset='6'/>
  <vcpupin vcpu='5' cpuset='7'/>
  <vcpupin vcpu='6' cpuset='8'/>
  <vcpupin vcpu='7' cpuset='9'/>
</cputune>
```

### Hugepages
Allocate hugepages for VM memory:
```bash
# Add to /etc/sysctl.conf
vm.nr_hugepages = 4096

# Apply
sudo sysctl -p
```

VM XML:
```xml
<memoryBacking>
  <hugepages/>
</memoryBacking>
```

### Disk I/O
Use virtio-scsi with SSD and direct I/O:
```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native'/>
  <source file='/var/lib/libvirt/images/gpu-worker-vm.qcow2'/>
  <target dev='sda' bus='scsi'/>
</disk>
```

## Security Hardening

### SELinux/AppArmor
Keep enabled and configure policies for libvirt.

### Firewall in VM
```bash
# Allow only homelab access
sudo ufw default deny incoming
sudo ufw allow from 192.168.1.170 to any port 11434 # Ollama
sudo ufw allow from 192.168.1.170 to any port 8188  # ComfyUI
sudo ufw allow from 192.168.1.0/24 to any port 22   # SSH
sudo ufw enable
```

### Minimal Services
Disable unnecessary services in VM:
```bash
sudo systemctl list-unit-files --type=service --state=enabled
sudo systemctl disable <unnecessary-service>
```

### Regular Updates
```bash
# Add to VM crontab
0 3 * * * apt update && apt upgrade -y && apt autoremove -y
```

## Troubleshooting

### GPU Not Detected in VM
- Verify IOMMU enabled: `dmesg | grep -i iommu`
- Check VFIO binding: `lspci -nnk -d <gpu-id>`
- Verify XML has correct PCI addresses
- Check for UEFI firmware (not BIOS)

### VM Won't Start
- Check libvirt logs: `sudo journalctl -u libvirtd`
- Verify GPU not in use by host
- Check VM XML syntax: `virsh define vm.xml`

### Poor Performance
- Enable CPU pinning
- Use hugepages
- Verify CPU governor: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`
- Should be "performance" not "powersave"

### Display Issues on Host
- Verify iGPU enabled in BIOS
- Check display connected to iGPU port
- Set iGPU as primary in BIOS

## Comparison: Container vs VM

| Aspect | Docker Container | VM with GPU Passthrough |
|--------|------------------|-------------------------|
| Setup Complexity | Low | High |
| Performance | ~Native | ~95% native |
| Isolation | Process-level | Hardware-level |
| Security | Good | Excellent |
| Resource Overhead | Minimal | ~5-10% |
| Backup/Snapshot | Volumes | Full VM image |
| Portability | Very High | Medium |
| Host GPU Access | Shared | Requires switching |

## References
- [VFIO GPU Passthrough Guide](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [libvirt Domain XML](https://libvirt.org/formatdomain.html)
- [NVIDIA vGPU Documentation](https://docs.nvidia.com/grid/)
- [Looking Glass Project](https://looking-glass.io/)
