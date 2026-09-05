#!/bin/bash
set -e

# ============================================================
# Arch Linux Installation Script for MacBook A1181
# Hostname: Ereshkigal | WM: i3-gaps | Shell: fish
# ============================================================

# --- Configuration ---
HOSTNAME="Ereshkigal"
LOCALE="pt_PT.UTF-8"
TIMEZONE="Europe/Lisbon"  # Adjust if needed (e.g., America/Sao_Paulo)
USERNAME="david"          # Change to your desired username

# --- Color Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo ./arch-install.sh)"
fi

if ! grep -qi "arch" /etc/os-release 2>/dev/null; then
    warn "This doesn't appear to be Arch Linux. Proceed with caution."
    read -p "Continue anyway? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
fi

clear
echo "============================================"
echo "  Arch Linux Install - MacBook A1181"
echo "  Hostname: $HOSTNAME"
echo "============================================"
echo ""
echo "This will install:"
echo "  - i3-gaps (lightweight tiling WM)"
echo "  - PipeWire (audio)"
echo "  - fish shell"
echo "  - Firefox, yay, TLP"
echo "  - Intel graphics, WiFi, Bluetooth"
echo ""
read -p "Ready to begin? (y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1

# --- Partitioning ---
info "Detecting disks..."
lsblk -d -o NAME,SIZE,MODEL
echo ""
echo "Available disks:"
select disk in $(lsblk -d -n -o NAME | sed 's/^/\/dev\/'); do
    [[ -n "$disk" ]] && break
    echo "Invalid selection"
done

info "Using disk: $disk"
warn "ALL DATA ON $disk WILL BE DESTROYED!"
read -p "Type 'YES' to confirm: " confirm
[[ "$confirm" != "YES" ]] && exit 1

# Partition the disk (UEFI assumed for A1181 with EFI)
info "Partitioning $disk..."

# Create GPT partition table
parted -s "$disk" mklabel gpt

# Create partitions
# 1: EFI System Partition (512MB)
# 2: Root partition (rest of disk)
parted -s "$disk" mkpart primary fat32 1MiB 513MiB
parted -s "$disk" set 1 esp on
parted -s "$disk" mkpart primary ext4 513MiB 100%

PART_ROOT="${disk}2"
PART_EFI="${disk}1"

# Wait for partitions to appear
sleep 2
partprobe "$disk"
sleep 2

# Format partitions
info "Formatting partitions..."
mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 "$PART_ROOT"

# Mount partitions
info "Mounting partitions..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

# --- Base System Installation ---
info "Installing base system..."
pacstrap /mnt base linux linux-firmware linux-headers nano networkmanager wireless-tools wpa_supplicant

# Generate fstab
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot Configuration ---
info "Configuring system in chroot..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# --- Timezone ---
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# --- Locale ---
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE.UTF-8" > /etc/locale.conf

# --- Hostname ---
echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1   $HOSTNAME" >> /etc/hosts

# --- mkinitcpio ---
sed -i 's/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystem fsck)/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystem fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# --- Bootloader (auto-detect) ---
if [ -d /sys/firmware/efi ]; then
    echo "UEFI detected - installing systemd-boot"
    bootctl install
    mkdir -p /boot/loader/entries
    cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
console-mode max
editor no
LOADER

    # Get root UUID
    ROOT_UUID=\$(blkid -s UUID -o value "$PART_ROOT")

    cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw
ENTRY
else
    echo "BIOS detected - installing GRUB"
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$disk"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# --- User Setup ---
echo "Setting root password..."
passwd

useradd -m -G wheel -s /bin/fish "$USERNAME"
echo "Set password for $USERNAME:"
passwd "$USERNAME"

# Enable sudo for wheel group
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- Package Installation ---
info "Installing packages..."

# Core packages
pacman -S --noconfirm \
    i3-wm i3lock i3status dmenu rofi \
    xorg-server xorg-xinit xorg-xrandr xorg-xbacklight xorg-xsetroot \
    picom unclutter \
    fish \
    firefox \
    pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber \
    bluez bluez-utils \
    tlp tlp-rdw \
    network-manager-applet \
    git base-devel \
    python \
    jre-openjdk \
    neovim \
    htop tree unzip wget curl \
    xdg-utils xdg-user-dirs \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-font-awesome \
    feh mpv mpd ncmpcpp \
    grim slurp wl-clipboard \
    xclip \
    fastfetch

# --- AUR Helper (yay) ---
info "Installing yay..."
sudo -u "$USERNAME" bash <<YAY
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
YAY

# --- VS Code (from AUR) ---
info "Installing VS Code..."
sudo -u "$USERNAME" yay -S --noconfirm visual-studio-code-bin

# --- Services ---
info "Enabling services..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable tlp
systemctl enable tlp-sleep
systemctl enable reflector.timer

# --- i3 Configuration ---
info "Setting up i3 config..."
sudo -u "$USERNAME" mkdir -p /home/$USERNAME/.config/i3
cat > /home/$USERNAME/.config/i3/config <<I3
# i3 config for MacBook A1181 - Ereshkigal

set \$mod Mod4

# Font
font pango:Noto Sans 10

# Terminal
bindsym \$mod+Return exec alacritty

# Kill window
bindsym \$mod+Shift+q kill

# Application launcher
bindsym \$mod+d exec rofi -show drun

# Focus
bindsym \$mod+h focus left
bindsym \$mod+j focus down
bindsym \$mod+k focus up
bindsym \$mod+l focus right

# Move
bindsym \$mod+Shift+h move left
bindsym \$mod+Shift+j move down
bindsym \$mod+Shift+k move up
bindsym \$mod+Shift+l move right

# Splits
bindsym \$mod+b split h
bindsym \$mod+v split v

# Fullscreen
bindsym \$mod+f fullscreen toggle

# Layout
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split

# Float
bindsym \$mod+Shift+space floating toggle
bindsym \$mod+space focus mode_toggle

# Workspaces
bindsym \$mod+1 workspace 1
bindsym \$mod+2 workspace 2
bindsym \$mod+3 workspace 3
bindsym \$mod+4 workspace 4
bindsym \$mod+5 workspace 5
bindsym \$mod+6 workspace 6
bindsym \$mod+7 workspace 7
bindsym \$mod+8 workspace 8
bindsym \$mod+9 workspace 9

# Move to workspace
bindsym \$mod+Shift+1 move container to workspace 1
bindsym \$mod+Shift+2 move container to workspace 2
bindsym \$mod+Shift+3 move container to workspace 3
bindsym \$mod+Shift+4 move container to workspace 4
bindsym \$mod+Shift+5 move container to workspace 5
bindsym \$mod+Shift+6 move container to workspace 6
bindsym \$mod+Shift+7 move container to workspace 7
bindsym \$mod+Shift+8 move container to workspace 8
bindsym \$mod+Shift+9 move container to workspace 9

# Restart / Exit
bindsym \$mod+Shift+c reload
bindsym \$mod+Shift+r restart
bindsym \$mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"

# Resize mode
mode "resize" {
    bindsym h resize shrink width 5 px or 5 ppt
    bindsym j resize grow height 5 px or 5 ppt
    bindsym k resize shrink height 5 px or 5 ppt
    bindsym l resize grow width 5 px or 5 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym \$mod+r mode "resize"

# Wallpaper
exec_always feh --bg-fill ~/.config/wallpaper.jpg

# Autostart
exec_always picom --config ~/.config/picom.conf
exec_always unclutter --timeout 3
exec_always nm-applet
exec_always blueman-applet
I3

# --- Picom Config ---
info "Setting up picom..."
cat > /home/$USERNAME/.config/picom.conf <<PICOM
backend = "glx";
vsync = true;
opacity-rule = [
    "100:class_g = 'firefox'",
    "100:class_g = 'Code'"
];
PICOM

# --- fish Config ---
info "Setting up fish shell..."
sudo -u "$USERNAME" mkdir -p /home/$USERNAME/.config/fish
cat > /home/$USERNAME/.config/fish/config.fish <<FISH
# fish config for Ereshkigal

# Aliases
alias ll 'ls -la'
alias la 'ls -a'
alias update 'sudo pacman -Syu'
alias yayupdate 'yay -Syu'
alias gs 'git status'
alias gp 'git push'
alias gc 'git commit -m'

# Environment
set -gx EDITOR nvim
set -gx BROWSER firefox

# Starship prompt (install manually if desired)
# starship init fish | source
FISH

# --- Alacritty Config ---
info "Setting up alacritty..."
sudo -u "$USERNAME" mkdir -p /home/$USERNAME/.config/alacritty
cat > /home/$USERNAME/.config/alacritty/alacritty.toml <<'ALACRITTY'
[window]
padding = { x = 5, y = 5 }
opacity = 0.95

[font]
size = 11.0

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"
ALACRITTY

# --- LightDM Config ---
info "Configuring LightDM..."
cat > /etc/lightdm/lightdm.conf <<LIGHTDM
[Seat:*]
user-session=i3
greeter-session=lightdm-gtk-greeter
LIGHTDM

# --- Fix permissions ---
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "  Hostname:  $HOSTNAME"
echo "  User:      $USERNAME"
echo "  WM:        i3-gaps"
echo "  Shell:     fish"
echo "  Audio:     PipeWire"
echo ""
echo "  Next steps:"
echo "  1. Reboot: reboot"
echo "  2. Login and i3 starts automatically"
echo "  3. Mod4+Return = terminal"
echo "  4. Mod4+d = app launcher (rofi)"
echo ""
echo "  Optional:"
echo "  - Set wallpaper: cp image.jpg ~/.config/wallpaper.jpg"
echo "  - Install starship: yay -S starship-bin"
echo "  - Install ttf-jetbrains-mono-nerd for icons"
echo ""
EOF

info "Script finished. Reboot to enjoy your new system!"
echo ""
read -p "Reboot now? (y/N): " reboot_confirm
if [[ "$reboot_confirm" == "y" || "$reboot_confirm" == "Y" ]]; then
    umount -R /mnt
    reboot
fi
