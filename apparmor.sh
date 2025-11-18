#!/bin/bash

# =============================================================================
# ARCH LINUX SECURITY HARDENING - LEVEL 2: APPARMOR (LIMINE EDITION)
# =============================================================================
# Reference: Guida Operativa 3.2 (Adattata per Limine)
# Description: Installa AppArmor e configura i parametri LSM nel kernel.
# =============================================================================

# --- Configurazioni Estetiche ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BOLD}${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${BOLD}${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${BOLD}${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${BOLD}${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    clear
    echo -e "${BOLD}${PURPLE}"
    echo "    ___  __________  ___  ___  __  ________  ___ "
    echo "   / _ |/ _/ _/ _  |/ _ \/ _ \/  |/  / __ \/ _ \\"
    echo "  / __ / _/ _/ __ / , _/ // / /|_/ / /_/ / , _/"
    echo " /_/ |_\_/_//_/ |_\_|_/____/_/  /_/\____/_/|_| "
    echo -e "      MANDATORY ACCESS CONTROL (MAC) SETUP${NC}"
    echo ""
    echo "Questo script attiverà AppArmor e configurerà il Kernel."
    echo "Bootloader target: LIMINE"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "Questo script richiede i permessi di root."
    fi
}

# --- Main Logic ---

banner
check_root

echo -n "Vuoi procedere con l'abilitazione di AppArmor? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_err "Operazione annullata."
fi

# 1. Installazione Pacchetti
log_info "Installazione pacchetto AppArmor..."
pacman -S --noconfirm --needed apparmor || log_err "Installazione fallita."
log_success "Pacchetto installato."

# 2. Abilitazione Servizio
log_info "Abilitazione servizio systemd..."
systemctl enable --now apparmor.service || log_err "Impossibile abilitare il servizio."
log_success "Servizio apparmor.service abilitato."

# 3. Configurazione Kernel (Limine)
log_info "Configurazione parametri Kernel in Limine..."

LIMINE_CONF="/boot/limine.conf"
LSM_PARAMS="lsm=landlock,lockdown,yama,integrity,apparmor,bpf"

if [ ! -f "$LIMINE_CONF" ]; then
    log_err "Non trovo $LIMINE_CONF. Assicurati che Limine sia installato correttamente."
fi

# Controllo se i parametri sono già presenti per evitare duplicati
if grep -q "apparmor" "$LIMINE_CONF"; then
    log_warn "Sembra che AppArmor sia già presente in $LIMINE_CONF."
    log_warn "Salto la modifica del bootloader per sicurezza."
else
    # Backup
    cp "$LIMINE_CONF" "$LIMINE_CONF.bak-apparmor"
    log_info "Backup creato in $LIMINE_CONF.bak-apparmor"

    # Iniezione Parametri
    # Cerca le righe che iniziano con 'cmdline:' (anche indentate) e appende la stringa alla fine
    sed -i "/^[[:space:]]*cmdline:/ s/$/ $LSM_PARAMS/" "$LIMINE_CONF"
    
    if grep -q "$LSM_PARAMS" "$LIMINE_CONF"; then
        log_success "Parametri LSM iniettati correttamente in $LIMINE_CONF."
    else
        log_err "Qualcosa è andato storto con la modifica di $LIMINE_CONF."
    fi
fi

# 4. Info Finali
echo ""
echo -e "${BOLD}${GREEN}SETUP COMPLETATO!${NC}"
echo "-----------------------------------------------------"
echo -e "AppArmor è installato e configurato."
echo -e "Per renderlo effettivo, devi ${BOLD}RIAVVIARE${NC} il sistema."
echo ""
echo "Dopo il riavvio, verifica lo stato con:"
echo -e "${BOLD}sudo aa-status${BOLD}${NC}"
echo "-----------------------------------------------------"
echo "Riavvia ora: reboot"
