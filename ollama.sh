#!/bin/bash

# Variables
CTID=100                  # LXC Container ID
HOSTNAME="ollama-lxc"     # Hostname for the container
PASSWORD="securepassword" # Root password for the container
CORES=50                  # Number of CPU cores
MEMORY=75000              # Memory in MB (75GB)
STORAGE="100"             # Storage in GB (100GB)
GPU_DRIVER_VERSION="570.86.15" # NVIDIA Driver version
GPU_DRIVER_URL="https://us.download.nvidia.com/tesla/570.86.15/NVIDIA-Linux-x86_64-570.86.15.run"

# Create the LXC container
echo "Creating LXC container..."
pct create $CTID \
  local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --cores $CORES \
  --memory $MEMORY \
  --storage local-lvm \
  --rootfs $STORAGE \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp

# Start the container
echo "Starting LXC container..."
pct start $CTID

# Wait for the container to boot
echo "Waiting for container to boot..."
sleep 10

# Add NVIDIA GPU passthrough configuration to the LXC container
echo "Configuring NVIDIA GPU passthrough..."
cat <<EOF >> /etc/pve/lxc/$CTID.conf
# NVIDIA GPU Passthrough
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 235:* rwm
lxc.cgroup2.devices.allow: c 510:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uv
