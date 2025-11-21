#!/bin/bash

# ==============================================================================
#  APPARMOR MAC ENABLER
# ==============================================================================
#  1. Installazione AppArmor e Audit framework
#  2. Iniezione parametri LSM (Landlock, Lockdown, Yama, Integrity, AppArmor, BPF)
#  3. Aggiornamento configurazioni ibride (GRUB + UKI cmdline)
#  4. Attivazione servizi e caricamento profili
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

ICON_SHIELD="[🛡️]"
ICON_DOC="[📄]"
ICON_GEAR="[⚙]"
ICON_WARN="[!]"
ICON_CHECK="[✔]"

# Parametri Kernel Richiesti
LSM_PARAMS="lsm=landlock,lockdown,yama,integrity,apparmor,bpf"

# File Configurazione
GRUB_CONF="/etc/default/grub"
CMDLINE_FILE="/etc/kernel/cmdline"

# --- FUNZIONI ---

log_header() { echo -e "\n${PURPLE}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_CHECK} $1${NC}"; }
log_info() { echo -e "${BLUE}${ICON_GEAR} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

# --- MAIN ---

clear
echo -e "${BLUE}${BOLD}"
echo "     _  ___ ___  _   ___ __  __  ___  ___ "
echo "    /_\/ _ \ _ \/_\ | _ \  \/  |/ _ \| _ \\"
echo "   / _ \  _/  _/ _ \|   / |\/| | (_) |   /"
echo "  /_/ \_\_| |_/_/ \_\_|_\_|  |_|\___/|_|_\ "
echo "       MANDATORY ACCESS CONTROL SETUP      "
echo -e "${NC}"
echo -e "${BLUE}==========================================${NC}"

check_root

# 1. INSTALLAZIONE PACCHETTI
log_header "1. Installazione Componenti AppArmor"

PACKAGES="apparmor audit python-psutil"
# Aggiungiamo apparmor-profiles se vuoi i profili extra, ma la guida cita "confina app vulnerabili"
# quindi è meglio averli come base.
PACKAGES="$PACKAGES apparmor-profiles"

log_info "Installazione: $PACKAGES..."
if pacman -S --needed --noconfirm $PACKAGES > /dev/null 2>&1; then
    log_success "Pacchetti installati."
else
    echo -e "${RED}Errore installazione pacchetti.${NC}"
    exit 1
fi

# 2. CONFIGURAZIONE PARAMETRI KERNEL (GRUB)
log_header "2. Configurazione Kernel Parameters (GRUB)"

if [[ -f "$GRUB_CONF" ]]; then
    # Backup
    cp "$GRUB_CONF" "$GRUB_CONF.bak.aa"
    
    # Controllo se già presenti
    if grep -q "lsm=" "$GRUB_CONF"; then
        echo -e "${YELLOW}${ICON_WARN} Parametri LSM sembrano già presenti in GRUB.${NC}"
        echo -e "   Verifica manuale: $(grep "lsm=" $GRUB_CONF)"
    else
        log_info "Iniezione parametri in GRUB_CMDLINE_LINUX_DEFAULT..."
        # Aggiunge i parametri in coda alla riga esistente
        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$LSM_PARAMS /" "$GRUB_CONF"
        log_success "GRUB aggiornato."
    fi
else
    echo -e "${RED}${ICON_WARN} File $GRUB_CONF non trovato!${NC}"
fi

# 3. CONFIGURAZIONE PARAMETRI KERNEL (UKI / CMDLINE)
log_header "3. Configurazione Kernel Parameters (UKI/Cmdline)"

if [[ -f "$CMDLINE_FILE" ]]; then
    # Backup
    cp "$CMDLINE_FILE" "$CMDLINE_FILE.bak.aa"
    
    if grep -q "lsm=" "$CMDLINE_FILE"; then
        echo -e "${YELLOW}${ICON_WARN} Parametri LSM già presenti in $CMDLINE_FILE.${NC}"
    else
        log_info "Append parametri a $CMDLINE_FILE..."
        # Aggiunge in fondo alla riga
        sed -i "s/$/ $LSM_PARAMS/" "$CMDLINE_FILE"
        log_success "Cmdline UKI aggiornata."
    fi
else
    echo -e "${YELLOW}${ICON_WARN} $CMDLINE_FILE non trovato (Forse non usi UKI?). Salto.${NC}"
fi

# 4. ATTIVAZIONE SERVIZI
log_header "4. Attivazione Servizi Systemd"

log_info "Abilitazione apparmor.service..."
systemctl enable apparmor --now &> /dev/null
log_success "AppArmor Service abilitato."

log_info "Abilitazione auditd.service (Logging)..."
systemctl enable auditd --now &> /dev/null
log_success "Auditd Service abilitato."


# 5. RIGENERAZIONE BOOTLOADER & UKI
log_header "5. Applicazione Modifiche (Rigenerazione)"

echo -e "   ${ICON_GEAR} Rigenerazione Configurazione GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null
log_success "GRUB rigenerato."

if [[ -f "/etc/mkinitcpio.d/linux-zen.preset" ]]; then
    echo -e "   ${ICON_GEAR} Rigenerazione UKI (mkinitcpio)..."
    mkinitcpio -P &> /dev/null
    log_success "UKI rigenerate con i nuovi parametri."
    
    # Se avevamo lo script di firma automatica (dal passo 3.2), lo lanciamo per sicurezza
    if [[ -x "/usr/local/bin/sign-assets.sh" ]]; then
        echo -e "   ${ICON_DOC} Firma UKI aggiornate..."
        /usr/local/bin/sign-assets.sh > /dev/null
        log_success "UKI firmate."
    fi
fi

# 6. VERIFICA STATO
echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}${BOLD}   APPARMOR CONFIGURATO   ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "Lo stato attuale è:"
aa-status --enabled 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Attivo (Kernel support detected)${NC}"
else
    echo -e "${YELLOW}Inattivo (Richiede Riavvio)${NC}"
fi
echo ""
echo -e "Al prossimo riavvio, verifica con: ${BOLD}aa-status${BOLD}"
echo -e "I profili extra sono installati ma non enforced di default."
echo -e "Per confinare un'app (es. firefox), installa il profilo extra e riavvia AppArmor."
echo ""
