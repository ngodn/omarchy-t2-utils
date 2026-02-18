#!/bin/bash

# T2 Linux GPU Switcher Script
# Manages Intel iGPU and AMD dGPU configuration
# Bootloader: Limine

set -e

APPLE_GMUX_CONF="/etc/modprobe.d/apple-gmux.conf"
BLACKLIST_CONF="/etc/modprobe.d/gpu-blacklist.conf"
AMDGPU_DPM_RULES="/etc/udev/rules.d/30-amdgpu-pm.rules"
BACKUP_DIR="/home/eins0fx/.gpu-switcher-backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ─── Privilege Escalation ──────────────────────────────────────────────────────

# Re-launches the script as root automatically.
# pkexec = graphical polkit prompt (GUI sessions)
# sudo   = terminal fallback
# Called once at the top of main() — no need to guard individual functions.
ensure_root() {
    [[ $EUID -eq 0 ]] && return 0

    print_status "Root privileges required — requesting elevation..."

    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec --disable-internal-agent bash "$0" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    else
        print_error "Neither pkexec nor sudo found. Please run as root manually."
        exit 1
    fi
}

# ─── Limine Config Discovery ───────────────────────────────────────────────────

find_limine_config() {
    local candidates=(
        "/boot/EFI/arch-limine/limine.conf"
        "/boot/EFI/BOOT/limine.conf"
        "/boot/EFI/limine/limine.conf"
        "/boot/limine/limine.conf"
        "/boot/limine.conf"
    )

    for path in "${candidates[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    print_error "Limine config not found in any known location"
    exit 1
}

# ─── Backup & Restore ──────────────────────────────────────────────────────────

create_backup() {
    local limine_config
    limine_config="$(find_limine_config)"

    print_status "Creating backup of current configuration..."
    mkdir -p "$BACKUP_DIR"

    [[ -f "$APPLE_GMUX_CONF" ]]  && cp "$APPLE_GMUX_CONF"  "$BACKUP_DIR/apple-gmux.conf.bak"
    [[ -f "$BLACKLIST_CONF" ]]   && cp "$BLACKLIST_CONF"    "$BACKUP_DIR/gpu-blacklist.conf.bak"
    [[ -f "$AMDGPU_DPM_RULES" ]] && cp "$AMDGPU_DPM_RULES" "$BACKUP_DIR/30-amdgpu-pm.rules.bak"
    cp "$limine_config" "$BACKUP_DIR/limine.conf.bak"

    # Save which config file we backed up so restore knows where to put it back
    echo "$limine_config" > "$BACKUP_DIR/limine_config_path"

    # Save current kernel cmdline for reference
    cat /proc/cmdline > "$BACKUP_DIR/cmdline.bak"

    print_success "Backup created in $BACKUP_DIR"
    print_status "Backed up limine config from: $limine_config"
}

restore_backup() {
    print_status "Restoring previous configuration..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "No backup found in $BACKUP_DIR"
        exit 1
    fi

    if [[ ! -f "$BACKUP_DIR/limine_config_path" ]]; then
        print_error "Backup is missing limine config path record"
        exit 1
    fi

    local limine_config
    limine_config="$(cat "$BACKUP_DIR/limine_config_path")"

    [[ -f "$BACKUP_DIR/apple-gmux.conf.bak" ]]    && cp "$BACKUP_DIR/apple-gmux.conf.bak"    "$APPLE_GMUX_CONF"
    [[ -f "$BACKUP_DIR/limine.conf.bak" ]]         && cp "$BACKUP_DIR/limine.conf.bak"         "$limine_config"
    [[ -f "$BACKUP_DIR/30-amdgpu-pm.rules.bak" ]] && cp "$BACKUP_DIR/30-amdgpu-pm.rules.bak" "$AMDGPU_DPM_RULES"

    # Remove files that were created by this script (not present at backup time)
    [[ -f "$BLACKLIST_CONF" ]] && rm -f "$BLACKLIST_CONF"
    [[ -f "$AMDGPU_DPM_RULES" && ! -f "$BACKUP_DIR/30-amdgpu-pm.rules.bak" ]] && rm -f "$AMDGPU_DPM_RULES"

    update_system
    print_success "Configuration restored from backup"
}

# ─── Limine cmdline Helpers ────────────────────────────────────────────────────

# Add a kernel parameter to ALL cmdline: lines in limine.conf (if not already present)
limine_add_param() {
    local config="$1"
    local param="$2"

    awk -v param="$param" '
        /^[[:space:]]*cmdline:/ {
            if (index($0, param) == 0) {
                sub(/cmdline:[[:space:]]*/, "cmdline: ")
                $0 = $0 " " param
            }
        }
        { print }
    ' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"

    print_status "Added '$param' to all cmdline entries in limine.conf"
}

# Remove a kernel parameter (and its =value variant) from ALL cmdline: lines
limine_remove_param() {
    local config="$1"
    local param_prefix="$2"   # e.g. "i915.enable_guc" matches "i915.enable_guc=2"

    sed -i -E "s/ ${param_prefix}(=[^ ]+)?//g" "$config"
    print_status "Removed '${param_prefix}' from all cmdline entries in limine.conf"
}

# ─── GPU Mode Configuration ────────────────────────────────────────────────────

configure_intel_only() {
    print_status "Configuring Intel GPU only..."
    local limine_config
    limine_config="$(find_limine_config)"

    # Enable iGPU via apple-gmux
    printf '# Enable the iGPU by default if present\noptions apple-gmux force_igd=y\n' > "$APPLE_GMUX_CONF"

    # Blacklist AMD GPU
    printf '# Blacklist AMD GPU for Intel-only mode\nblacklist amdgpu\nblacklist radeon\n' > "$BLACKLIST_CONF"

    # Remove AMD DPM udev rules — AMD GPU blacklisted, rules would be a no-op
    [[ -f "$AMDGPU_DPM_RULES" ]] && rm -f "$AMDGPU_DPM_RULES"

    # Ensure Intel GUC is enabled in kernel cmdline
    limine_remove_param "$limine_config" "i915.enable_guc"
    limine_add_param    "$limine_config" "i915.enable_guc=2"

    print_success "Intel GPU only configuration applied"
}

configure_amd_only() {
    print_status "Configuring AMD GPU only..."
    local limine_config
    limine_config="$(find_limine_config)"

    # Disable iGPU via apple-gmux
    printf '# Disable the iGPU to use dGPU\noptions apple-gmux force_igd=n\n' > "$APPLE_GMUX_CONF"

    # Blacklist Intel GPU
    printf '# Blacklist Intel GPU for AMD-only mode\nblacklist i915\n' > "$BLACKLIST_CONF"

    # Configure AMD GPU DPM for low power by default
    printf '# Set AMD GPU to low power mode by default\nSUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="low"\n' > "$AMDGPU_DPM_RULES"

    # Remove Intel GUC parameter — not useful without i915
    limine_remove_param "$limine_config" "i915.enable_guc"

    print_success "AMD GPU only configuration applied"
}

configure_hybrid() {
    print_status "Configuring hybrid graphics (both GPUs available)..."
    local limine_config
    limine_config="$(find_limine_config)"

    # Allow both GPUs, prefer dGPU via apple-gmux
    printf '# Allow both GPUs - hybrid mode\noptions apple-gmux force_igd=n\n' > "$APPLE_GMUX_CONF"

    # Remove any GPU blacklists
    [[ -f "$BLACKLIST_CONF" ]] && rm -f "$BLACKLIST_CONF"

    # Configure AMD GPU DPM for low power by default
    printf '# Set AMD GPU to low power mode by default in hybrid mode\nSUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="low"\n' > "$AMDGPU_DPM_RULES"

    # Keep Intel GUC enabled for better iGPU performance in hybrid
    limine_remove_param "$limine_config" "i915.enable_guc"
    limine_add_param    "$limine_config" "i915.enable_guc=2"

    print_success "Hybrid graphics configuration applied"
}

# ─── System Update ─────────────────────────────────────────────────────────────

update_system() {
    print_status "Updating system configuration..."

    # Regenerate initramfs so blacklist/modprobe changes take effect at boot
    mkinitcpio -P

    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger

    # NOTE: No grub-mkconfig needed — Limine reads limine.conf directly at boot.
    print_success "System configuration updated"
}

# ─── Status ────────────────────────────────────────────────────────────────────

show_current_status() {
    # Inline discovery — avoids calling find_limine_config in a subshell where
    # its internal `exit 1` only kills the subshell, making the || fallback unreachable.
    local limine_config=""
    for path in \
        "/boot/EFI/arch-limine/limine.conf" \
        "/boot/EFI/BOOT/limine.conf" \
        "/boot/EFI/limine/limine.conf" \
        "/boot/limine/limine.conf" \
        "/boot/limine.conf"; do
        if [[ -f "$path" ]]; then
            limine_config="$path"
            break
        fi
    done

    echo -e "\n${BLUE}=== Current GPU Status ===${NC}"

    echo -e "\n${YELLOW}Loaded GPU drivers:${NC}"
    lsmod | grep -E "(i915|amdgpu)" || echo "No GPU drivers loaded"

    echo -e "\n${YELLOW}Active GPU (OpenGL):${NC}"
    if command -v glxinfo >/dev/null 2>&1; then
        glxinfo | grep -E "(OpenGL vendor|OpenGL renderer)" || echo "Unable to detect"
    else
        echo "glxinfo not available (install mesa-utils)"
    fi

    echo -e "\n${YELLOW}Apple GMux config:${NC}"
    [[ -f "$APPLE_GMUX_CONF" ]] && cat "$APPLE_GMUX_CONF" || echo "Not configured"

    echo -e "\n${YELLOW}GPU blacklist:${NC}"
    [[ -f "$BLACKLIST_CONF" ]] && cat "$BLACKLIST_CONF" || echo "No blacklists"

    echo -e "\n${YELLOW}AMD DPM udev rule:${NC}"
    [[ -f "$AMDGPU_DPM_RULES" ]] && cat "$AMDGPU_DPM_RULES" || echo "No DPM rules configured"

    echo -e "\n${YELLOW}Current AMD DPM level (live):${NC}"
    local dpm_path
    dpm_path="$(ls /sys/bus/pci/drivers/amdgpu/*/power_dpm_force_performance_level 2>/dev/null | head -1)"
    if [[ -n "$dpm_path" ]]; then
        cat "$dpm_path"
    else
        echo "AMD GPU not found or not loaded"
    fi

    echo -e "\n${YELLOW}Limine config location:${NC}"
    if [[ -z "$limine_config" ]]; then
        echo "(not found)"
    else
        echo "$limine_config"

        echo -e "\n${YELLOW}Limine cmdline entries:${NC}"
        grep -n "cmdline:" "$limine_config" || echo "No cmdline entries found"
    fi

    echo -e "\n${YELLOW}Running kernel cmdline (current boot):${NC}"
    cat /proc/cmdline
}

# ─── AMD DPM ───────────────────────────────────────────────────────────────────

set_amd_dpm() {
    local mode="$1"
    if [[ "$mode" != "low" && "$mode" != "high" ]]; then
        print_error "Invalid DPM mode. Use 'low' or 'high'"
        return 1
    fi

    print_status "Setting AMD DPM to $mode performance level..."

    if [[ -f "$AMDGPU_DPM_RULES" ]]; then
        sed -i -E "s/=\"(low|high)\"/=\"${mode}\"/g" "$AMDGPU_DPM_RULES"
        print_success "AMD DPM udev rule updated to $mode"
    else
        print_warning "No AMD DPM rules found. Run amd-only or hybrid mode first."
        return 1
    fi

    # Apply immediately if AMD GPU is loaded
    local dpm_path
    dpm_path="$(ls /sys/bus/pci/drivers/amdgpu/*/power_dpm_force_performance_level 2>/dev/null | head -1)"
    if [[ -n "$dpm_path" ]]; then
        echo "$mode" | tee "$dpm_path" >/dev/null
        print_success "AMD DPM immediately set to $mode"
    else
        print_warning "AMD GPU not currently loaded. Changes will take effect after reboot."
    fi

    udevadm control --reload-rules
    udevadm trigger
}

# ─── Help ──────────────────────────────────────────────────────────────────────

show_help() {
    echo "T2 Linux GPU Switcher (Limine)"
    echo "Usage: sudo $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  intel-only    Configure Intel GPU only (power saving)"
    echo "  amd-only      Configure AMD GPU only (performance)"
    echo "  hybrid        Configure both GPUs (hybrid mode)"
    echo "  restore       Restore previous configuration"
    echo "  status        Show current GPU status"
    echo "  amd-dpm-low   Set AMD DPM to low power (thermal management)"
    echo "  amd-dpm-high  Set AMD DPM to high performance (gaming/rendering)"
    echo "  help          Show this help message"
    echo ""
    echo "Note: This script requires root privileges and will:"
    echo "  - Modify /etc/modprobe.d/ configurations"
    echo "  - Edit limine.conf kernel cmdline parameters directly"
    echo "  - Configure AMD DPM via udev rules"
    echo "  - Regenerate initramfs (mkinitcpio -P)"
    echo "  - Require a reboot to take effect (except DPM changes)"
    echo ""
    echo "Limine config is discovered from these locations (first match wins):"
    echo "  /boot/EFI/arch-limine/limine.conf"
    echo "  /boot/EFI/BOOT/limine.conf"
    echo "  /boot/EFI/limine/limine.conf"
    echo "  /boot/limine/limine.conf"
    echo "  /boot/limine.conf"
}

# ─── Interactive Menu ──────────────────────────────────────────────────────────

show_menu() {
    echo -e "\n${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      T2 Linux GPU Switcher           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}\n"
    echo -e "  ${YELLOW}1)${NC} Intel GPU only    (power saving)"
    echo -e "  ${YELLOW}2)${NC} AMD GPU only      (performance)"
    echo -e "  ${YELLOW}3)${NC} Hybrid            (both GPUs)"
    echo -e "  ${YELLOW}4)${NC} AMD DPM → low     (thermal management)"
    echo -e "  ${YELLOW}5)${NC} AMD DPM → high    (gaming / rendering)"
    echo -e "  ${YELLOW}6)${NC} Restore backup"
    echo -e "  ${YELLOW}7)${NC} Show current status"
    echo -e "  ${YELLOW}q)${NC} Quit\n"
}

confirm() {
    local prompt="$1"
    local answer
    echo -e "\n${YELLOW}${prompt}${NC} [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

interactive_mode() {
    while true; do
        show_menu
        read -rp "Choose an option: " choice

        case "$choice" in
            1)
                confirm "Switch to Intel GPU only? (requires reboot)" || continue
                create_backup
                configure_intel_only
                update_system
                print_warning "Reboot required for changes to take effect"
                ;;
            2)
                confirm "Switch to AMD GPU only? (requires reboot)" || continue
                create_backup
                configure_amd_only
                update_system
                print_warning "Reboot required for changes to take effect"
                ;;
            3)
                confirm "Switch to Hybrid mode? (requires reboot)" || continue
                create_backup
                configure_hybrid
                update_system
                print_warning "Reboot required for changes to take effect"
                ;;
            4)
                confirm "Set AMD DPM to low power?" || continue
                set_amd_dpm "low"
                ;;
            5)
                confirm "Set AMD DPM to high performance?" || continue
                set_amd_dpm "high"
                ;;
            6)
                confirm "Restore backup configuration? (requires reboot)" || continue
                restore_backup
                print_warning "Reboot required for changes to take effect"
                ;;
            7)
                show_current_status
                ;;
            q|Q)
                echo -e "\n${BLUE}Bye!${NC}"
                exit 0
                ;;
            *)
                print_error "Invalid option: '$choice'"
                ;;
        esac

        echo -e "\nPress Enter to return to menu..."
        read -r
    done
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    # Elevate once here — all code below runs as root
    ensure_root "$@"

    # If no args given, drop into interactive menu
    if [[ $# -eq 0 ]]; then
        interactive_mode
        return
    fi

    # Otherwise keep supporting direct command-line usage
    case "${1}" in
        "intel-only")
            create_backup
            configure_intel_only
            update_system
            print_warning "Reboot required for changes to take effect"
            ;;
        "amd-only")
            create_backup
            configure_amd_only
            update_system
            print_warning "Reboot required for changes to take effect"
            ;;
        "hybrid")
            create_backup
            configure_hybrid
            update_system
            print_warning "Reboot required for changes to take effect"
            ;;
        "restore")
            restore_backup
            print_warning "Reboot required for changes to take effect"
            ;;
        "status")
            show_current_status
            ;;
        "amd-dpm-low")
            set_amd_dpm "low"
            ;;
        "amd-dpm-high")
            set_amd_dpm "high"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            print_error "Unknown option: '${1}'"
            show_help
            exit 1
            ;;
    esac
}

main "$@"