#!/bin/bash
set -euo pipefail

# Arch Linux Installation Script
# This script automates the Arch installation process using archinstall
# and performs post-installation configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/archinstall-config.json"
POST_INSTALL_SCRIPT="${SCRIPT_DIR}/post-install.sh"
AUR_INSTALL_SCRIPT="${SCRIPT_DIR}/aur-install.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Verify we're running as root
if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root"
  exit 1
fi

# Verify archinstall is installed
if ! command -v archinstall &>/dev/null; then
  print_error "archinstall not found. Install it with: pacman -S archinstall"
  exit 1
fi

# Verify configs exist
if [[ ! -f "$CONFIG_FILE" ]]; then
  print_error "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

if [[ ! -f "$POST_INSTALL_SCRIPT" ]]; then
  print_error "Post-install script not found: $POST_INSTALL_SCRIPT"
  exit 1
fi

if [[ ! -f "$AUR_INSTALL_SCRIPT" ]]; then
  print_error "AUR install script not found: $AUR_INSTALL_SCRIPT"
  exit 1
fi

# Check for network connectivity
print_header "Checking Network Connectivity"
if ! ping -c 1 archlinux.org &>/dev/null; then
  print_error "No network connectivity. Please configure network and try again."
  exit 1
fi
print_success "Network connectivity verified"

print_header "Arch Linux Installation"

# Show disk info
print_header "Available Disks"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

echo ""
print_warning "WARNING: This will ERASE /dev/nvme0n1 completely!"
read -p "Continue with installation? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  print_warning "Installation cancelled"
  exit 0
fi

# Run archinstall with config
print_header "Running archinstall..."
archinstall --config="${CONFIG_FILE}" --silent || {
  print_error "archinstall failed"
  exit 1
}

print_success "Base system installation complete"

# Determine mount point - archinstall may use /mnt or /mnt/archinstall
print_header "Preparing post-installation..."
MOUNT_POINT=""
for mp in /mnt/archinstall /mnt; do
  if [[ -d "$mp/root" ]]; then
    MOUNT_POINT="$mp"
    break
  fi
done

if [[ -z "$MOUNT_POINT" ]]; then
  print_warning "Mount point not found. Attempting to mount /dev/nvme0n1p3 to /mnt"
  mount /dev/nvme0n1p3 /mnt || {
    print_error "Failed to mount root partition"
    print_warning "Copy post-install scripts manually to the new system"
    exit 1
  }
  MOUNT_POINT="/mnt"
fi

print_success "Found mount point: $MOUNT_POINT"

# Copy post-install scripts to new system
if [[ -d "$MOUNT_POINT/root" ]]; then
  cp "$POST_INSTALL_SCRIPT" "$MOUNT_POINT/root/post-install.sh"
  cp "$AUR_INSTALL_SCRIPT" "$MOUNT_POINT/root/aur-install.sh"
  chmod +x "$MOUNT_POINT/root/post-install.sh"
  chmod +x "$MOUNT_POINT/root/aur-install.sh"

  print_success "Post-installation scripts copied to /root/"
else
  print_error "Root directory not found in mount point"
  print_warning "Copy scripts manually to the new system"
fi

print_header "Installation Complete!"
print_success "System installation finished"
echo ""
echo "Next steps:"
echo "1. Reboot into the new system"
echo "2. Run as root: sudo /root/post-install.sh"
echo "3. After first login as gyarepyon, run: /root/aur-install.sh"
echo "4. Clone your dotfiles repository"
echo "5. Enjoy!"
echo ""
read -p "Press Enter to continue..."
