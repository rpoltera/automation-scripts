#!/usr/bin/env bash

# Load the ProxmoxVE helper functions
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 tteck
# Author: havardthom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openwebui.com/

APP="Open WebUI with NVIDIA GPU Passthrough"
var_tags="ai;interface;gpu"
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

# Install Node.js >= 20.x
msg_info "Installing Node.js >= 20.x..."
pct exec $CTID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
pct exec $CTID -- bash -c "apt install -y nodejs"

# Verify Node.js installation
msg_info "Verifying Node.js installation..."
pct exec $CTID -- node --version
pct exec $CTID -- npm --version

# Install Open WebUI
msg_info "Installing Open WebUI..."
pct exec $CTID -- bash -c "apt update && apt install -y git python3-pip python3-venv"
pct exec $CTID -- bash -c "git clone https://github.com/open-webui/open-webui.git /opt/open-webui"
pct exec $CTID -- bash -c "cd /opt/open-webui && npm install"
pct exec $CTID -- bash -c "cd /opt/open-webui && npm run build"
pct exec $CTID -- bash -c "cd /opt/open-webui/backend && python3 -m venv venv"
pct exec $CTID -- bash -c "cd /opt/open-webui/backend && source venv/bin/activate && pip install -r requirements.txt"

# Start Open WebUI service
msg_info "Starting Open WebUI service..."
pct exec $CTID -- bash -c "cd /opt/open-webui && npm start &"

# Display completion message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access Open WebUI using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
