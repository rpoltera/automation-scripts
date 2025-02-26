#!/bin/bash

# Variables
HOSTNAME="ollama-lxc"     # Hostname for the container
PASSWORD="securepassword" # Root password for the container
CORES=50                  # Number of CPU cores
MEMORY=75000              # Memory in MB (75GB)
STORAGE="100"             # Storage in GB (100GB)
GPU_DRIVER_VERSION="570.86.15" # NVIDIA Driver version
GPU_DRIVER_URL="https://us.download.nvidia.com/tesla/570.86.15/NVIDIA-Linux-x86_64-570.86.15.run"

# Function to find the next available LXC ID
find_next_ctid() {
  local last_ctid=$(pct list | awk 'NR>1 {print $1}' | sort -n | tail -1)
  if [ -z "$last_ctid" ]; then
    echo 118
  else
    echo $((last_ctid + 1))
  fi
}

# Get the next available CTID
CTID=$(find_next_ctid)
echo "Next available CTID: $CTID"

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
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
EOF

# Restart the container to apply changes
echo "Restarting container to apply GPU passthrough configuration..."
pct restart $CTID

# Install NVIDIA Driver in the LXC container
echo "Installing NVIDIA Driver in the container..."
pct exec $CTID -- bash -c "apt update && apt install -y curl build-essential"
pct exec $CTID -- bash -c "curl -O $GPU_DRIVER_URL"
pct exec $CTID -- bash -c "chmod +x NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run"
pct exec $CTID -- bash -c "./NVIDIA-Linux-x86_64-$GPU_DRIVER_VERSION.run --silent"

# Verify NVIDIA Driver installation
echo "Verifying NVIDIA Driver installation..."
pct exec $CTID -- nvidia-smi

# Install Ollama in the LXC container
echo "Installing Ollama..."
pct exec $CTID -- bash -c "curl -fsSL https://ollama.ai/install.sh | sh"

# Start Ollama service
echo "Starting Ollama service..."
pct exec $CTID -- systemctl enable ollama
pct exec $CTID -- systemctl start ollama

# Print completion message
echo "LXC container setup for Ollama with NVIDIA GPU passthrough is complete!"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Access the container using: pct enter $CTID"
