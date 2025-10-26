#!/bin/bash
set -euo pipefail

# Post-Installation Configuration Script
# Run this after the base Arch installation completes

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

print_header "Post-Installation Configuration"

# System hostname and locale are already set by archinstall
# But let's ensure they're correct
print_header "Verifying System Configuration"
hostnamectl set-hostname archpad || true
localectl set-locale LANG=C.UTF-8 || true
timedatectl set-timezone Asia/Tokyo || true
print_success "System configuration verified"

# Create primary user
print_header "Creating User Account"
if ! id -u gyarepyon &>/dev/null; then
  useradd -m -s /bin/fish -G wheel,kvm,libvirt,docker gyarepyon
  print_success "User 'gyarepyon' created"

  # Prompt for password
  echo "Set password for gyarepyon:"
  passwd gyarepyon
else
  print_warning "User 'gyarepyon' already exists"
fi

# Configure sudoers
print_header "Configuring Sudoers"
if [[ ! -f /etc/sudoers.d/wheel ]]; then
  echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/wheel
  chmod 0440 /etc/sudoers.d/wheel

  # Validate sudoers file
  if visudo -c -f /etc/sudoers.d/wheel; then
    print_success "Wheel group configured for sudo"
  else
    print_error "Sudoers file validation failed"
    rm -f /etc/sudoers.d/wheel
    exit 1
  fi
else
  print_warning "Sudoers already configured"
fi

# Configure NetworkManager
print_header "Configuring NetworkManager"
mkdir -p /etc/NetworkManager/conf.d/
cat >/etc/NetworkManager/conf.d/custom.conf <<'EOF'
[main]
plugins=ifupdown,keyfile
dhcp=dhclient

[ifupdown]
managed=false
EOF
print_success "NetworkManager configured"

# Enable and start services
print_header "Enabling System Services"
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable systemd-resolved
systemctl enable ufw
systemctl enable libvirtd
systemctl enable systemd-timesyncd
systemctl enable docker

print_success "Services enabled"

# Configure UFW
print_header "Configuring Firewall (UFW)"
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force allow 22/tcp  # SSH
ufw --force allow 80/tcp  # HTTP
ufw --force allow 443/tcp # HTTPS
ufw --force enable
print_success "UFW configured and enabled"

# Set up SMB credentials
print_header "Configuring SMB Share"
mkdir -p /mnt/momonga
mkdir -p /etc/samba

# Create credential file for SMB
if [[ ! -f /etc/samba/credentials ]]; then
  cat >/etc/samba/credentials <<'EOF'
username=
password=
EOF
  chmod 600 /etc/samba/credentials
  chown root:root /etc/samba/credentials

  print_warning "SMB credentials file created at /etc/samba/credentials"
  print_warning "Edit /etc/samba/credentials with your SMB username and password"
  print_warning "Format:"
  print_warning "  username=your_username"
  print_warning "  password=your_password"
else
  print_warning "SMB credentials file already exists"
fi

# Update fstab with SMB mount
if ! grep -q "momonga" /etc/fstab; then
  cat >>/etc/fstab <<'EOF'

# SMB share
//192.168.50.155/momonga             /mnt/momonga    cifs    credentials=/etc/samba/credentials,uid=1000,gid=1000,iocharset=utf8,_netdev,noauto,x-systemd.automount    0      0
EOF
  print_success "SMB mount added to fstab (automount on access)"
else
  print_warning "SMB mount already in fstab"
fi

# Install GRUB theme
print_header "Installing GRUB Theme"
GRUB_THEME_DIR="/boot/grub/themes/catppuccin-mocha-grub-theme"
if [[ ! -d "$GRUB_THEME_DIR" ]]; then
  mkdir -p "$GRUB_THEME_DIR"
  print_warning "Manual GRUB theme installation required"
  print_warning "Clone catppuccin-mocha-grub-theme to $GRUB_THEME_DIR"
  print_warning "Then run: grub-mkconfig -o /boot/grub/grub.cfg"
else
  print_success "GRUB theme directory exists"
fi

# Configure GRUB
print_header "Updating GRUB Configuration"
if grep -q "^#GRUB_THEME=" /etc/default/grub; then
  sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"${GRUB_THEME_DIR}/theme.txt\"|" /etc/default/grub
elif grep -q "^GRUB_THEME=" /etc/default/grub; then
  sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"${GRUB_THEME_DIR}/theme.txt\"|" /etc/default/grub
else
  echo "GRUB_THEME=\"${GRUB_THEME_DIR}/theme.txt\"" >>/etc/default/grub
fi

if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
  sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=5|' /etc/default/grub
else
  echo "GRUB_TIMEOUT=5" >>/etc/default/grub
fi

if grep -q "^GRUB_TIMEOUT_STYLE=" /etc/default/grub; then
  sed -i 's|^GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=menu|' /etc/default/grub
else
  echo "GRUB_TIMEOUT_STYLE=menu" >>/etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB configuration updated"

# Configure greetd for auto-login (optional)
print_header "Configuring Greetd"
if [[ -f /etc/greetd/config.toml ]]; then
  print_warning "Greetd already configured. Skipping."
else
  mkdir -p /etc/greetd
  cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "agreety --cmd /bin/fish"
user = "greeter"
EOF
  systemctl enable greetd
  print_success "Greetd configured (manual login)"
  print_warning "To enable auto-login, edit /etc/greetd/config.toml"
fi

# Create home directories
print_header "Setting Up Home Directories"
sudo -u gyarepyon mkdir -p /home/gyarepyon/{Documents,Downloads,Pictures,Videos,Projects,Music}
print_success "Home directories created"

# Create script for user to run after first login
print_header "Creating User Setup Script"
cat >/home/gyarepyon/first-login-setup.sh <<'EOF'
#!/bin/bash
# First Login Setup Script
# Run this after your first login as gyarepyon

set -euo pipefail

echo "=== First Login Setup ==="

# Enable user systemd services
echo "Enabling user services..."
systemctl --user enable pipewire.socket
systemctl --user enable wireplumber.service
systemctl --user start pipewire.socket
systemctl --user start wireplumber.service

echo "✓ User services enabled"

# Initialize rustup
if command -v rustup &>/dev/null; then
  echo "Initializing Rust..."
  rustup default stable
  echo "✓ Rust initialized"
fi

echo ""
echo "=== Setup Complete ==="
echo "Next steps:"
echo "1. Run /root/aur-install.sh to install AUR packages"
echo "2. Clone your dotfiles repository"
echo "3. Configure your environment"
echo ""
EOF

chown gyarepyon:gyarepyon /home/gyarepyon/first-login-setup.sh
chmod +x /home/gyarepyon/first-login-setup.sh
print_success "First login setup script created at /home/gyarepyon/first-login-setup.sh"

# Final touches
print_header "Finalizing Installation"

# Ensure proper permissions
chown -R gyarepyon:gyarepyon /home/gyarepyon
chmod 755 /home/gyarepyon

# Clean pacman cache
pacman -Sc --noconfirm

print_success "Post-installation configuration complete!"
echo ""
echo -e "${GREEN}=== Next Steps ===${NC}"
echo "1. Edit /etc/samba/credentials with your SMB credentials"
echo "2. Reboot the system"
echo "3. Login as gyarepyon"
echo "4. Run: ~/first-login-setup.sh"
echo "5. Run as root: sudo /root/aur-install.sh"
echo "6. Clone your dotfiles repository:"
echo "   git clone <your-dotfiles-repo> ~/.dotfiles"
echo "7. Apply your dotfiles configuration"
echo ""
echo -e "${YELLOW}Note:${NC} You may need to manually configure WiFi connections"
echo "Use: nmcli device wifi connect <SSID> password <password>"
echo ""
read -p "Press Enter to continue..."
