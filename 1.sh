#!/usr/bin/env bash

# Load the ProxmoxVE helper functions
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 tteck
# Author: poltera 
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Adapted for Ollama with NVIDIA GPU Passthrough

APP="Ollama"
var_tags="ai,gpu"
var_cpu="50"              # Number of CPU cores
var_ram="75048"           # Memory in MB (75GB)
var_disk="100"            # Storage in GB (100GB)
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

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/ollama ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  UPD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUPPORT" --radiolist --cancel-button Exit-Script "Spacebar = Select" 10 59 2 \
    "1" "Update LXC" ON \
    "2" "Reinstall NVIDIA Driver" OFF \
    3>&1 1>&2 2>&3)
  if [ "$UPD" == "1" ]; then
    msg_info "Updating ${APP} LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated ${APP} LXC"
    exit
  fi
  if [ "$UPD" == "2" ]; then
    msg_info "Reinstalling NVIDIA Driver"
    $STD curl -O $GPU_DRIVER_URL
    $STD chmod +x NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run
    $STD ./NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run --silent
    msg_ok "Reinstalled NVIDIA Driver"
    exit
  fi
}

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

# Restart the container to apply changes
msg_info "Restarting container to apply GPU passthrough configuration..."
pct restart $CTID

# Set up NVIDIA repositories (if needed)
msg_info "Setting up NVIDIA repositories..."
pct exec $CTID -- bash -c "curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-docker.gpg"
pct exec $CTID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/nvidia-docker.gpg] https://nvidia.github.io/libnvidia-container/stable/deb12/$(dpkg --print-architecture) /' > /etc/apt/sources.list.d/nvidia-docker.list"
pct exec $CTID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/nvidia-docker.gpg] https://nvidia.github.io/nvidia-container-runtime/stable/deb12/$(dpkg --print-architecture) /' >> /etc/apt/sources.list.d/nvidia-docker.list"

# Install NVIDIA Driver in the LXC container
msg_info "Installing NVIDIA Driver in the container..."
pct exec $CTID -- bash -c "apt update && apt install -y curl build-essential"
pct exec $CTID -- bash -c "curl -O $GPU_DRIVER_URL"
pct exec $CTID -- bash -c "chmod +x NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run"
pct exec $CTID -- bash -c "./NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run --silent"

# Verify NVIDIA Driver installation
msg_info "Verifying NVIDIA Driver installation..."
pct exec $CTID -- nvidia-smi

# Install Ollama in the LXC container
msg_info "Installing Ollama..."
pct exec $CTID -- bash -c "curl -fsSL https://ollama.ai/install.sh | sh"

# Start Ollama service
msg_info "Starting Ollama service..."
pct exec $CTID -- systemctl enable ollama
pct exec $CTID -- systemctl start ollama

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following command:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}p
