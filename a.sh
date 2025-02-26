#!/usr/bin/env bash

# Load the ProxmoxVE helper functions
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 tteck
# Author: poltera
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Adapted for NVIDIA GPU Passthrough and Docker Setup

APP="NVIDIA GPU Passthrough with Docker"
var_tags="gpu,docker"
var_cpu="4"               # Number of CPU cores
var_ram="8192"            # Memory in MB (8GB)
var_disk="50"             # Storage in GB (50GB)
var_os="debian"           # OS template
var_version="12"          # Debian 12
var_unprivileged="0"      # Unprivileged container (0 for GPU passthrough)

# NVIDIA GPU Passthrough variables
GPU_DRIVER_VERSION="570.86.15"
GPU_DRIVER_URL="https://us.download.nvidia.com/tesla/570.86.15/NVIDIA-Linux-x86_64-570.86.15.run"

header_info "$APP"
variables
color
catch_errors

# Prompt for a password
read -s -p "Enter a password for the root user: " PASSWORD
echo

# Define STD variable for suppressing command output
STD=""

start
build_container

# Add NVIDIA GPU passthrough configuration to the LXC container
msg_info "Configuring NVIDIA GPU passthrough..."
cat <<EOF >> /etc/pve/lxc/$CTID.conf
# NVIDIA GPU Passthrough
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 235:* rwm
lxc.cgroup2.devices.allow: c 510:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
EOF

# Configure network settings
msg_info "Configuring network settings..."
cat <<EOF >> /etc/pve/lxc/$CTID.conf
# Network settings
net0: name=eth0,bridge=vmbr0,ip=dhcp
EOF

# Verify container exists
msg_info "Verifying container $CTID..."
if ! pct list | grep -q "$CTID"; then
  msg_error "Container $CTID does not exist!"
  exit 1
fi

# Start the container if it's not running
if pct status $CTID | grep -q "stopped"; then
  msg_info "Starting container $CTID..."
  pct start $CTID
fi

# Wait for the container to initialize
msg_info "Waiting for container $CTID to initialize..."
sleep 10

# Install necessary tools
msg_info "Installing gpg, curl, and ca-certificates..."
pct exec $CTID -- bash -c "apt update && apt install -y gpg curl ca-certificates"

# Install NVIDIA Driver in the LXC container
msg_info "Installing NVIDIA Driver..."
pct exec $CTID -- bash -c "wget $GPU_DRIVER_URL -O NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run"
pct exec $CTID -- bash -c "chmod +x NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run"
pct exec $CTID -- bash -c "./NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run --no-kernel-modules --silent"

# Verify NVIDIA Driver installation
msg_info "Verifying NVIDIA Driver installation..."
pct exec $CTID -- nvidia-smi

# Set up NVIDIA Container Toolkit
msg_info "Setting up NVIDIA Container Toolkit..."
pct exec $CTID -- bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
pct exec $CTID -- bash -c "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
pct exec $CTID -- bash -c "apt update && apt install -y nvidia-container-toolkit"

# Modify NVIDIA Container Toolkit configuration
msg_info "Modifying NVIDIA Container Toolkit configuration..."
pct exec $CTID -- bash -c "sed -i 's/no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml"

# Install Docker
msg_info "Installing Docker..."
pct exec $CTID -- bash -c "install -m 0755 -d /etc/apt/keyrings"
pct exec $CTID -- bash -c "curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
pct exec $CTID -- bash -c "chmod a+r /etc/apt/keyrings/docker.gpg"
pct exec $CTID -- bash -c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
pct exec $CTID -- bash -c "apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

# Enable NVIDIA Container Toolkit with Docker
msg_info "Enabling NVIDIA Container Toolkit with Docker..."
pct exec $CTID -- bash -c "nvidia-ctk runtime configure --runtime=docker"
pct exec $CTID -- bash -c "systemctl restart docker"

# Install Dockge Docker Container Manager
msg_info "Installing Dockge Docker Container Manager..."
pct exec $CTID -- bash -c "mkdir -p /opt/stacks /opt/dockge"
pct exec $CTID -- bash -c "cd /opt/dockge && curl https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml --output compose.yaml"
pct exec $CTID -- bash -c "cd /opt/dockge && docker compose up -d"

# Display completion message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access Dockge using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://<LXC_IP>:5001${CL}"
echo -e "${INFO}${YW} Replace <LXC_IP> with the actual IP address of the LXC container.${CL}"
