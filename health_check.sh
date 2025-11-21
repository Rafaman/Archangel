#!/bin/bash

# ==============================================================================
#  ARCH LINUX SYSTEM AUDITOR
# ==============================================================================
#  Verifica lo stato di salute e sicurezza post-hardening.
#  Analizza: Boot, Kernel, Storage, Rete, MAC, Desktop.
# ==============================================================================

# --- PALETTE COLORI ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- ICONE ---
PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

# --- FUNZIONI DI UTILITÀ ---

print_section() {
    echo -e "\n${CYAN}${BOLD}:: $1${NC}"
    echo -e "${BLUE}--------------------------------------------------${NC}"
}

check_result() {
    local description=$1
    local status=$2
    local hint=$3
    
    if [ "$status" -eq 0 ]; then
        printf "%-50s %b\n" "$description" "$PASS"
    else
        printf "%-50s %b\n" "$description" "$FAIL"
        if [ ! -z "$hint" ]; then
            echo -e "      ${YELLOW}↳ Fix: $hint${NC}"
        fi
    fi
}

check_kernel_param() {
    local param=$1
    local expected=$2
    local current=$(sysctl -n "$param" 2>/dev/null)
    
    if [ "$current" == "$expected" ]; then
        check_result "Sysctl: $param = $expected" 0
    else
        check_result "Sysctl: $param (Attuale: $current)" 1 "Esegui kernel_hardening.sh"
    fi
}

get_user() {
    echo ${SUDO_USER:-$USER}
}

# --- MAIN AUDIT ---

clear
echo -e "${PURPLE}${BOLD}"
echo "   ___  _   _  ___  ___  _____   __ "
echo "  / __|| | | |/ __||_ _||_   _| /  \\"
echo "  \__ \| |_| |\__ \ | |   | |  | () |"
echo "  |___/ \___/ |___/|_|_|  |_|   \__/"
echo "        SYSTEM INTEGRITY AUDIT      "
echo -e "${NC}"
echo -e "Data: $(date)"
echo -e "Kernel: $(uname -r)"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Esegui come root (sudo) per un audit completo.${NC}"
   exit 1
fi

# 1. ARCHITETTURA & KERNEL
print_section "1. Kernel & Boot Security"

# Check Zen Kernel
if uname -r | grep -q "zen"; then
    check_result "Kernel Zen in uso" 0
else
    check_result "Kernel Zen in uso" 1 "Installa linux-zen"
fi

# Check Secure Boot (shim)
if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    check_result "Secure Boot (UEFI) ATTIVO" 0
else
    # Fallback check per bootctl
    if bootctl status 2>/dev/null | grep -q "Secure Boot: enabled"; then
        check_result "Secure Boot (UEFI) ATTIVO" 0
    else
        check_result "Secure Boot (UEFI) ATTIVO" 1 "Abilita nel BIOS / Esegui setup_secureboot_uki.sh"
    fi
fi

# Check Hardening Params
check_kernel_param "kernel.kptr_restrict" "2"
check_kernel_param "kernel.dmesg_restrict" "1"
check_kernel_param "kernel.unprivileged_bpf_disabled" "1"

# 2. STORAGE & ENCRYPTION
print_section "2. Filesystem & Crittografia"

# Check Btrfs Mount Options (Flat Layout & SSD Opts)
# Cerca le flag cruciali impostate nel passo 2.3
MOUNT_OPTS=$(findmnt / -n -o OPTIONS)
if [[ "$MOUNT_OPTS" == *"zstd:1"* && "$MOUNT_OPTS" == *"discard=async"* ]]; then
    check_result "Btrfs SSD Opts (zstd:1, discard=async)" 0
else
    check_result "Btrfs SSD Opts (zstd:1, discard=async)" 1 "Verifica /etc/fstab (migrate_flat_layout.sh)"
fi

# Check Layout Flat (Verifica che root sia subvol=@)
if findmnt / -n -o SOURCE | grep -q "\[/@\]"; then
    check_result "Layout Flat (subvol=@ attivo)" 0
else
    check_result "Layout Flat (subvol=@ attivo)" 1 "Root non sembra montata su @"
fi

# Check TPM2 Binding (Cerca tpmrm0 e cryptsetup status)
# Verifica generica se esiste un device mappato con cryptsetup
if lsblk -f | grep -q "crypto_LUKS"; then
    check_result "Volume LUKS rilevato" 0
    
    if [ -c /dev/tpmrm0 ]; then
        check_result "Chip TPM 2.0 Rilevato" 0
        # Nota: Verificare il binding effettivo richiederebbe probing invasivo
    else
        check_result "Chip TPM 2.0 Rilevato" 1 "Abilita fTPM nel BIOS"
    fi
else
    check_result "Volume LUKS rilevato" 1 "Nessuna partizione cifrata montata?"
fi

# 3. RESILIENZA
print_section "3. Resilienza & Backup"

# Check Snapper Config
if snapper list-configs 2>/dev/null | grep -q "root"; then
    check_result "Configurazione Snapper 'root'" 0
else
    check_result "Configurazione Snapper 'root'" 1 "Esegui enable_resilience.sh"
fi

# Check Grub-Btrfs Daemon
if systemctl is-active --quiet grub-btrfsd.path; then
    check_result "Demone Grub-Btrfs (Auto-Update)" 0
else
    check_result "Demone Grub-Btrfs (Auto-Update)" 1 "systemctl enable grub-btrfsd.path"
fi

# 4. SICUREZZA ATTIVA (MAC & FIREWALL)
print_section "4. Access Control & Firewall"

# AppArmor
if aa-status --enabled 2>/dev/null; then
    check_result "AppArmor MAC attivo" 0
    # Conta profili enforced
    PROFILES=$(aa-status --json 2>/dev/null | grep -o '"mode": "enforce"' | wc -l)
    echo -e "      ${INFO} Profili Enforced: $PROFILES"
else
    check_result "AppArmor MAC attivo" 1 "Parametri kernel mancanti (enable_apparmor.sh)"
fi

# UFW Firewall
if ufw status | grep -q "Status: active"; then
    check_result "UFW Firewall attivo" 0
    if ufw status | grep -q "22/tcp.*LIMIT"; then
        check_result "Rate Limiting SSH (Anti-BruteForce)" 0
    else
        check_result "Rate Limiting SSH (Anti-BruteForce)" 1 "ufw limit ssh"
    fi
else
    check_result "UFW Firewall attivo" 1 "ufw enable"
fi

# Fail2Ban
if systemctl is-active --quiet fail2ban; then
    check_result "Fail2Ban Service" 0
else
    check_result "Fail2Ban Service" 1 "systemctl enable --now fail2ban"
fi

# 5. NETWORK PRIVACY
print_section "5. Network Privacy (DNS)"

# Check DNS-over-TLS
# Resolvectl status deve mostrare +DoT o porta 853
if resolvectl status | grep -E "\+DoT|DNSOverTLS=yes" &>/dev/null; then
    check_result "DNS-over-TLS (Systemd-resolved)" 0
else
    check_result "DNS-over-TLS (Systemd-resolved)" 1 "Controlla network_defense.sh"
fi

# Check Server Quad9 (Verifica se 9.9.9.9 è configurato)
if grep -q "9.9.9.9" /etc/systemd/resolved.conf.d/*.conf 2>/dev/null; then
    check_result "Provider DNS Sicuro (Quad9)" 0
else
    check_result "Provider DNS Sicuro (Quad9)" 1 "File config DoT non trovato"
fi

# 6. USER SPACE & APPS
print_section "6. User Space & Browser"

REAL_USER=$(get_user)
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Check Wayland
if env | grep -q "XDG_SESSION_TYPE=wayland"; then
    check_result "Sessione Wayland Attiva" 0
else
    # Potremmo essere in tty, quindi warn invece di fail
    echo -e "      ${WARN} Sessione attuale: $XDG_SESSION_TYPE (Atteso: wayland)"
fi

# Check Arkenfox
FIREFOX_PROFILE=$(find "$USER_HOME/.mozilla/firefox" -maxdepth 2 -name "user.js" 2>/dev/null | head -n 1)
if [[ -f "$FIREFOX_PROFILE" ]]; then
    check_result "Profilo Hardened (user.js trovato)" 0
else
    check_result "Profilo Hardened (user.js trovato)" 1 "Esegui harden_browser.sh"
fi

# Check Firejail (Deve essere ASSENTE)
if pacman -Qi firejail &> /dev/null; then
    check_result "Assenza Firejail (Clean Architecture)" 1 "Rimuovi firejail (conflitto sandbox)"
else
    check_result "Assenza Firejail (Clean Architecture)" 0
fi

# 7. MANUTENZIONE
print_section "7. Maintenance Automation"

# Check Paccache Hook
if [[ -f "/etc/pacman.d/hooks/paccache.hook" ]]; then
    check_result "Hook Pulizia Cache (paccache)" 0
else
    check_result "Hook Pulizia Cache (paccache)" 1 "Mancante (maintenance_setup.sh)"
fi

# Check Doas
if [[ -f "/etc/doas.conf" ]]; then
    check_result "Opendoas configurato" 0
else
    check_result "Opendoas configurato" 1 "Mancante (harden_privileges.sh)"
fi

echo ""
echo -e "${BLUE}==================================================${NC}"
echo -e "Audit completato. Controlla eventuali ${RED}[FAIL]${NC} sopra."
echo ""
