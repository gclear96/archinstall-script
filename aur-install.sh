#!/bin/bash
set -euo pipefail

# AUR Packages Installation Script
# Run this as root AFTER first login to install AUR packages
# This is separate because AUR packages should be built as a regular user

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if user exists
if ! id -u gyarepyon &>/dev/null; then
  print_error "User 'gyarepyon' does not exist. Run post-install.sh first."
  exit 1
fi

# Check for network connectivity
print_header "Checking Network Connectivity"
if ! sudo -u gyarepyon ping -c 1 aur.archlinux.org &>/dev/null; then
  print_error "No network connectivity to AUR. Please configure network and try again."
  exit 1
fi
print_success "Network connectivity verified"

# Install AUR helper (yay)
print_header "Installing AUR Helper (yay)"
if ! command -v yay &>/dev/null; then
  sudo -u gyarepyon bash <<'EOF'
set -euo pipefail
cd /tmp
if [[ -d /tmp/yay-bin ]]; then
  rm -rf /tmp/yay-bin
fi
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd /tmp
rm -rf yay-bin
EOF
  print_success "yay installed"
else
  print_warning "yay already installed"
fi

# Install base AUR dependencies first
print_header "Installing AUR Base Dependencies"
BASE_AUR_DEPS=(
  "gtk3"
  "gobject-introspection"
  "gtk-layer-shell"
)

for pkg in "${BASE_AUR_DEPS[@]}"; do
  if ! pacman -Q "$pkg" &>/dev/null; then
    print_warning "Installing dependency: $pkg"
    pacman -S --noconfirm "$pkg" || print_warning "Failed to install $pkg"
  fi
done

# Install AUR packages
print_header "Installing AUR Packages"
print_warning "This may take a while as packages are built from source..."

AUR_PACKAGES=(
  "1password"
  "visual-studio-code-bin"
  "discord"
  "rose-pine-cursor"
  "rose-pine-hyprcursor"
  "rofi-wayland"
  "walker-bin"
)

# Optional AGS packages - these may have complex dependencies
AGS_PACKAGES=(
  "aylurs-gtk-shell-git"
  "libastal-4-git"
  "ags-hyprpanel-git"
  "appmenu-glib-translator-git"
)

for pkg in "${AUR_PACKAGES[@]}"; do
  if ! pacman -Q "$pkg" &>/dev/null; then
    print_warning "Installing $pkg from AUR..."
    if sudo -u gyarepyon yay -S "$pkg" --noconfirm --removemake; then
      print_success "$pkg installed"
    else
      print_error "Failed to install $pkg - continuing anyway"
    fi
  else
    print_success "$pkg already installed"
  fi
done

print_header "Installing AGS Packages (Optional)"
print_warning "AGS packages may fail due to complex dependencies"
read -p "Install AGS packages? (y/n) " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
  for pkg in "${AGS_PACKAGES[@]}"; do
    if ! pacman -Q "$pkg" &>/dev/null; then
      print_warning "Installing $pkg from AUR..."
      if sudo -u gyarepyon yay -S "$pkg" --noconfirm --removemake; then
        print_success "$pkg installed"
      else
        print_error "Failed to install $pkg - skipping"
      fi
    else
      print_success "$pkg already installed"
    fi
  done
else
  print_warning "Skipping AGS packages"
fi

# Clean up
print_header "Cleaning Up"
sudo -u gyarepyon yay -Sc --noconfirm || true
pacman -Sc --noconfirm || true

print_success "AUR packages installation complete!"
echo ""
echo -e "${GREEN}=== Installation Summary ===${NC}"
echo "AUR helper (yay) is installed and configured"
echo "Core AUR packages have been installed"
echo ""
echo "You can now:"
echo "1. Install additional AUR packages with: yay -S <package>"
echo "2. Update all packages with: yay -Syu"
echo "3. Search AUR with: yay -Ss <search-term>"
echo ""
read -p "Press Enter to continue..."
