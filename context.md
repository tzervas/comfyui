### Key Points
- Research suggests rootless Docker commonly faces networking glitches, slower performance, and limitations in advanced features like resource controls, though it enhances security by avoiding root privileges.
- For a Debian 13 VM hosting Docker and Compose v2, evidence leans toward installing Docker via the official APT repository first, then configuring rootless mode with a dedicated non-root user for isolation, ensuring subordinate UID/GID mappings are set.
- Libvirt, virt-manager, and virt-viewer can operate in session mode for rootless use, with users added to relevant groups like libvirt-qemu, allowing non-root VM management while maintaining security.
- SSH key-based access with role-based controls appears effective by creating scoped users, disabling password logins, and using authorized_keys restrictions to limit commands and prevent data risks.

### Common Issues with Rootless Docker
Rootless Docker mitigates security risks but introduces trade-offs. Networking often fails due to driver incompatibilities or updates, requiring troubleshooting like verifying RootlessKit setups. Performance can lag, especially for I/O-intensive tasks, compared to rootful mode. Feature limitations include no support for cgroups resource controls, AppArmor profiles, or overlay networks in some cases. Setup complexity arises from needing proper UID/GID mappings and disabling the system daemon to avoid conflicts.

### Recommended Docker Setup on Debian 13 VM
Install Docker Engine via APT for reliability on Debian 13 (Trixie). For rootless, create a dedicated user (e.g., dockeruser), ensure /etc/subuid and /etc/subgid have 65,536+ entries, and use dockerd-rootless-setuptool.sh. Docker Compose v2 works seamlessly in rootless mode once the environment is set. This isolates services without constant sudo.

### Libvirt and Related Tools Setup
Configure libvirt in session mode (qemu:///session) for rootless operation. Add users to libvirt or kvm groups for /dev/kvm access. Virt-manager connects to user sessions after removing system connections and adding session ones. Virt-viewer follows similarly for viewing VMs.

### Secure SSH with Role-Based Access
Generate per-user SSH keys, disable password authentication in /etc/ssh/sshd_config, and use authorized_keys with options like no-port-forwarding or command restrictions for scoping. Create role-specific users (e.g., docker-admin) with group memberships and sudoers entries for limited commands, ensuring LAN-only access via firewall rules.

---
### Setting Up a Secure Debian 13 VM for Rootless Docker and Virtualization

This comprehensive guide outlines a secure, isolated setup for a Debian 13 (Trixie) host running as a virtual machine (VM), focused on rootless Docker with Docker Compose v2, alongside rootless libvirt for virtualization tools like virt-manager and virt-viewer. The approach emphasizes role-based access controls (RBAC) through dedicated users, minimizing root usage, and securing SSH with key-based authentication to prevent unauthorized actions or data loss. All steps are drawn from official documentation and verified practices, assuming a fresh Debian 13 installation. We'll cover prerequisites, installations, configurations, and security hardening, including potential pitfalls and best practices.

#### Prerequisites and System Preparation
Before diving in, ensure your Debian 13 VM meets these requirements:
- **Hardware/VM Setup**: Enable nested virtualization in your hypervisor (e.g., Proxmox or KVM host) if the VM will run nested VMs via libvirt. Allocate at least 4GB RAM, 2 CPUs, and 50GB disk for testing Docker and VMs.
- **Update System**: Run `sudo apt update && sudo apt upgrade -y` to ensure the latest packages.
- **Install Essentials**: `sudo apt install -y ca-certificates curl uidmap slirp4netns fuse-overlayfs` (for rootless Docker and user namespaces).
- **Disable Root SSH**: Edit `/etc/ssh/sshd_config` to set `PermitRootLogin no` and restart SSH: `sudo systemctl restart sshd`.
- **Firewall**: Enable UFW with `sudo apt install ufw; sudo ufw allow from 192.168.0.0/24 to any port 22; sudo ufw enable` (adjust for your LAN subnet).
- **User Namespace Mappings**: For rootless operations, edit `/etc/subuid` and `/etc/subgid` to allocate ranges (e.g., add `username:100000:65536` for each user). This is critical to avoid "no subordinate IDs" errors.

| Component | Minimum Requirement | Rationale |
|-----------|---------------------|-----------|
| RAM | 4GB | Supports multiple containers/VMs without swapping. |
| CPU | 2 cores with VT-x/AMD-V | Enables efficient virtualization; nested if hosting VMs. |
| Disk | 50GB | Accommodates Docker images, VM disks, and logs. |
| Kernel | 6.1+ (Debian 13 default) | Supports user namespaces and cgroups v2 for rootless. |

#### Common Issues with Rootless Docker and Mitigation
Rootless Docker runs the daemon and containers without root privileges, using user namespaces for isolation. However, it introduces several challenges based on community reports and official docs:

- **Networking Problems**: Drivers like RootlessKit may fail after updates, causing container connectivity issues. Mitigate by verifying `ip link` and using `--network host` for simple cases, or switch to slirp4netns for user-mode networking.
- **Performance Degradation**: Slower I/O due to overlayfs in user space; tests show up to 50% slower database setups. Use volumes with bind mounts and monitor with `docker stats`.
- **Feature Limitations**: No cgroups for resource limits, AppArmor, checkpoint/restore, or certain overlays. For workloads needing these, consider Podman as an alternative.
- **Setup Complexity**: Requires precise UID/GID setup; conflicts with system daemon. Always disable the rootful daemon first: `sudo systemctl disable --now docker.service docker.socket`.
- **Container Root Behavior**: Processes appear as root inside containers but map to user IDs on host. Specify non-root users in Dockerfiles for added security.

To troubleshoot, check logs with `journalctl --user -u docker` and ensure `newuidmap`/`newgidmap` are installed.

#### Recommended Rootless Docker Setup with Dedicated User
For a secure Debian 13 setup, install Docker first, then configure rootless mode under a non-sudoer user for isolation. This ensures daily tasks (e.g., `docker ps`, Compose) run without elevation.

1. **Install Docker Engine**:
   - Set up APT repo: Follow the steps to add Docker's key and sources.list.
   - Install: `sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`.
   - Verify: `sudo docker run hello-world`.

2. **Create Dedicated Docker User**:
   - `sudo adduser dockeruser --shell /bin/bash`.
   - Allocate UID/GID: Add `dockeruser:100000:65536` to `/etc/subuid` and `/etc/subgid`.
   - Switch: `su - dockeruser`.

3. **Install Rootless Docker**:
   - Install extras if needed: `sudo apt install docker-ce-rootless-extras` (as root, then switch back).
   - Run setup: `dockerd-rootless-setuptool.sh install`.
   - Add to `.bashrc`: `export PATH=/usr/bin:$PATH; export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock`.
   - Start: `systemctl --user start docker.service`.
   - Enable linger: `sudo loginctl enable-linger dockeruser` for boot persistence.

4. **Docker Compose v2 Integration**:
   - Compose is included as a plugin. Run `docker compose up` in rootless context; ensure volumes are owned by dockeruser to avoid permission issues.

5. **Permissions and Isolation**:
   - Bind mounts: Ensure paths like `/home/dockeruser/volumes` are user-owned.
   - Test: `docker run -d -p 8080:80 nginx` (ports above 1024 work rootless).

| Setup Step | Command | Notes |
|------------|---------|-------|
| User Creation | `sudo adduser dockeruser` | Non-sudoer for isolation. |
| Rootless Install | `dockerd-rootless-setuptool.sh install` | Handles systemd user service. |
| Verification | `docker info` | Should show "rootless" in security options. |

#### Rootless Libvirt, Virt-Manager, and Virt-Viewer Setup
Libvirt supports session mode for rootless VMs, isolating to user namespaces. This is ideal for a VM host, avoiding root for VM management.

1. **Install Packages**:
   - `sudo apt install -y qemu-kvm libvirt-clients libvirt-daemon virtinst virt-manager virt-viewer bridge-utils`.

2. **Create Dedicated VM User**:
   - `sudo adduser vmuser`.
   - Add to groups: `sudo usermod -aG kvm,libvirt-qemu vmuser` for /dev/kvm access.

3. **Configure Session Mode**:
   - As vmuser: Run `virsh uri` (should show `qemu:///session`).
   - In virt-manager: Delete QEMU system connection, add QEMU user session.
   - Networking: Use user-mode (Slirp) or setup a bridge: `sudo virsh net-start default` (requires root once).

4. **Create and Manage VMs**:
   - `virt-install --connect qemu:///session --name testvm --memory 2048 --disk size=20 --osinfo debian13 --location /path/to/iso`.
   - View: `virt-viewer --connect qemu:///session testvm`.

5. **Permissions**:
   - Disks/ISO in `/home/vmuser/.local/share/libvirt/images`.
   - Avoid system mode to prevent escalation.

| Tool | Rootless Config | Benefits |
|------|-----------------|----------|
| Libvirt | qemu:///session | User-isolated VMs. |
| Virt-Manager | User session connection | GUI without sudo. |
| Virt-Viewer | Session URI | Secure remote viewing. |

#### Secure SSH Setup with Role-Based Access Controls
To manage via LAN SSH without passwords, use keys with restrictions for RBAC-like controls. This prevents accidental data loss by scoping access.

1. **Global SSH Hardening**:
   - Edit `/etc/ssh/sshd_config`: Set `PasswordAuthentication no`, `PubkeyAuthentication yes`.
   - Restart: `sudo systemctl restart sshd`.

2. **Per-User Key Setup**:
   - On client: `ssh-keygen -t ed25519 -C "docker-access" -f ~/.ssh/docker_key`.
   - Copy public key: `ssh-copy-id dockeruser@host-ip` (initially allow passwords, then disable).
   - For vmuser: Repeat with a separate key.

3. **Scoped Permissions in authorized_keys**:
   - Edit `~dockeruser/.ssh/authorized_keys`: Prefix keys with `restrict,command="/usr/bin/docker ps",no-port-forwarding ssh-ed25519 AAA...` to limit to specific commands.
   - For vmuser: `restrict,command="virsh list --all",no-agent-forwarding ...`.
   - Groups/Sudoers: Add to `/etc/sudoers.d/docker`: `dockeruser ALL=(ALL) NOPASSWD: /usr/bin/docker *` for limited sudo on Docker commands only.

4. **RBAC Implementation**:
   - Roles: docker-admin (Docker only), vm-admin (libvirt only), full-admin (both, but minimal).
   - Audit: Enable logging in sshd_config with `LogLevel VERBOSE`.
   - Tools for Scale: Consider HashiCorp Vault for dynamic key management if users grow.

| Role | User Example | SSH Restrictions | Allowed Actions |
|------|--------------|------------------|-----------------|
| Docker Admin | dockeruser | Command="/usr/bin/docker *", no-X11-forwarding | Docker pull/build/run/compose. |
| VM Admin | vmuser | Command="virsh *", no-pty | VM create/start/stop via virsh. |
| Monitor | monitoruser | Command="/usr/bin/tail -f /var/log/*" | Log viewing only. |

#### Final Testing and Best Practices
- Test Docker: As dockeruser, `docker compose version` and deploy a sample stack.
- Test Libvirt: As vmuser, create a VM and connect via virt-viewer.
- SSH Test: From LAN, `ssh -i ~/.ssh/docker_key dockeruser@host-ip` – should only allow scoped commands.
- Monitoring: Use `fail2ban` for brute-force protection: `sudo apt install fail2ban`.
- Backups: Script user home dirs and configs; avoid storing secrets in images.
- Updates: Regularly `apt update` and restart services.
This setup provides solid isolation, reducing attack surfaces while enabling efficient management. If issues arise, consult logs and community forums for Debian-specific tweaks.

### Key Citations
- [Docker Rootless Troubleshooting](https://docs.docker.com/engine/security/rootless/troubleshoot/)
- [Experimenting with Rootless Docker](https://medium.com/%40tonistiigi/experimenting-with-rootless-docker-416c9ad8c0d6)
- [Slow Rootless Docker Performance](https://discussion.fedoraproject.org/t/slow-rootless-docker-performance/73739)
- [Install Docker on Debian](https://docs.docker.com/engine/install/debian/)
- [Rootless Mode Docker Docs](https://docs.docker.com/engine/security/rootless/)
- [How to Run Docker in Rootless Mode](https://thenewstack.io/how-to-run-docker-in-rootless-mode/)
- [Rootless Virtual Machines with KVM and QEMU](https://developers.redhat.com/articles/2024/12/18/rootless-virtual-machines-kvm-and-qemu)
- [HowTo: Unprivileged User Session in Virt-Manager](https://discussion.fedoraproject.org/t/howto-use-the-unprivileged-user-session-in-virt-manager-for-rootless-virtualization-with-qemu-and-kvm/127066)
- [How to Configure SSH Key-Based Authentication](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)
- [Top Tips to Secure SSH on Linux](https://www.blumira.com/blog/secure-ssh-on-linux)
- [How to Configure Key-Based Authentication for SSH](https://www.redhat.com/en/blog/key-based-authentication-ssh)
- [SSH Key Management Best Practices](https://www.beyondtrust.com/blog/entry/ssh-key-management-overview-6-best-practices)
- [Manage SSH Keys](https://serverfault.com/questions/824180/manage-ssh-keys)