#!/bin/bash

# ==============================================================================
#  ARCH RESILIENCE SYSTEM: SNAPPER & GRUB-BTRFS
# ==============================================================================
#  1. Configurazione Snapper per layout Btrfs Flat (@snapshots)
#  2. Integrazione Hooks Pacman (snap-pac)
#  3. Abilitazione Boot da Snapshot (grub-btrfs)
#  4. Configurazione Retention Policy (Evita disco pieno)
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_CAM="[📷]"
ICON_BOOT="[👢]"
ICON_GEAR="[⚙]"
ICON_CLEAN="[🧹]"
ICON_OK="[✔]"
ICON_WARN="[!]"

# File di configurazione Snapper
SNAP_CONF="/etc/snapper/configs/root"

# --- FUNZIONI ---

log_header() { echo -e "\n${BLUE}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_OK} $1${NC}"; }
log_info() { echo -e "${CYAN}${ICON_GEAR} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

install_pkg() {
    if ! pacman -Qi $1 &> /dev/null; then
        echo -e "${YELLOW}   Installazione mancante: $1...${NC}"
        pacman -S --noconfirm $1
    else
        echo -e "${GREEN}${ICON_OK} Presente: $1${NC}"
    fi
}

# --- MAIN ---

clear
echo -e "${CYAN}${BOLD}"
echo "   ___  _  _   _   ___  ___  ___  ___ "
echo "  / __|| \| | /_\ | _ \| _ \| __|| _ \\"
echo "  \__ \| .\` |/ _ \|  _/|  _/| _| |   /"
echo "  |___/|_|\_/_/ \_\_|  |_|  |___||_|_\ "
echo "       RESILIENCE AUTOMATION           "
echo -e "${NC}"
echo -e "${BLUE}======================================${NC}"

check_root

# 1. INSTALLAZIONE SOFTWARE
log_header "1. Verifica Componenti Software"
install_pkg "snapper"
install_pkg "snap-pac"
install_pkg "grub-btrfs"
# inotify-tools serve al demone grub-btrfsd per guardare le cartelle
install_pkg "inotify-tools" 

# 2. CONFIGURAZIONE SNAPPER (LA "DANZA" DEI SUBVOLUMI)
log_header "2. Inizializzazione Snapper (Flat Layout Fix)"

# Controlla se esiste già una config
if snapper list-configs | grep -q "root"; then
    echo -e "${GREEN}${ICON_OK} Configurazione 'root' già esistente.${NC}"
else
    log_info "Creazione configurazione root..."
    
    # TRICK CRITICO PER FLAT LAYOUT:
    # 1. Smontiamo il vero subvolume @snapshots
    umount /.snapshots 2>/dev/null
    
    # 2. Rimuoviamo la directory vuota
    rm -rf /.snapshots
    
    # 3. Creiamo la config (Snapper crea un subvolume .snapshots nested qui)
    snapper -c root create-config /
    
    # 4. Cancelliamo il subvolume nested che Snapper ha appena creato
    btrfs subvolume delete /.snapshots
    
    # 5. Ricreiamo la directory
    mkdir /.snapshots
    
    # 6. Rimontiamo il vero @snapshots (leggendo da fstab)
    mount -a
    
    # 7. Impostiamo permessi (Root only per sicurezza, o 750 per gruppo wheel)
    chmod 750 /.snapshots
    
    log_success "Snapper inizializzato correttamente su @snapshots."
fi

# 3. CONFIGURAZIONE RETENTION POLICY
log_header "3. Ottimizzazione Policy di Ritenzione"
# Modifichiamo /etc/snapper/configs/root per evitare di riempire il disco
# Teniamo:
# - TIMELINE: Disabilitato o ridotto (snapper standard usa cron, noi preferiamo eventi)
# - NUMBER: Importante per snap-pac (installazioni)

if [[ -f "$SNAP_CONF" ]]; then
    log_info "Applicazione best practices a $SNAP_CONF..."
    
    # Disabilita snapshot orari (timeline) per evitare overhead, ci affidiamo agli update
    # O li teniamo molto bassi
    sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' "$SNAP_CONF"
    
    # Limita snapshot numerici (quelli di pacman)
    # Tieni gli ultimi 10 importanti, non 50
    sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="10"/' "$SNAP_CONF"
    sed -i 's/^NUMBER_LIMIT_IMPORTANT="50"/NUMBER_LIMIT_IMPORTANT="5"/' "$SNAP_CONF"
    
    # Permetti al gruppo wheel di gestire snapper (opzionale, qui teniamo root)
    # sed -i 's/^ALLOW_GROUPS=""/ALLOW_GROUPS="wheel"/' "$SNAP_CONF"

    log_success "Policy applicate: Timeline OFF, Limit=10."
else
    echo -e "${RED}${ICON_WARN} File configurazione non trovato!${NC}"
fi

# 4. INTEGRAZIONE GRUB-BTRFS
log_header "4. Attivazione Bootloader Integration"

# Abilita il path unit che monitora /.snapshots
log_info "Abilitazione grub-btrfsd (monitoraggio realtime)..."
systemctl enable --now grub-btrfsd

# Forza una rigenerazione immediata per vedere se rileva lo snapshot 0/iniziale
echo -e "   ${ICON_BOOT} Rigenerazione menu GRUB..."
# grub-mkconfig rileverà gli snapshot se presenti
grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null

if systemctl is-active --quiet grub-btrfsd; then
    log_success "Demone grub-btrfs attivo."
else
    echo -e "${RED}${ICON_WARN} Il demone grub-btrfs non sembra attivo.${NC}"
fi

# 5. CREAZIONE PRIMO SNAPSHOT MANUALE
log_header "5. Creazione 'Baseline' Snapshot"
echo -e "${CYAN}Creazione snapshot iniziale 'System Ready'..."
snapper -c root create --description "Post-Installation Baseline"

# Aggiornamento grub manuale per includere questo snapshot
/etc/grub.d/41_snapshots-btrfs &> /dev/null

log_success "Snapshot base creato e indicizzato."

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}${BOLD}   RESILIENZA ATTIVATA   ${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "1. ${BOLD}snap-pac${NC}: Ogni 'pacman' genererà snapshot PRE e POST."
echo -e "2. ${BOLD}grub-btrfs${NC}: Troverai la voce 'Arch Linux Snapshots' al boot."
echo -e "3. ${BOLD}Rollback${NC}:"
echo -e "   Se il sistema si rompe:"
echo -e "   a) Riavvia e seleziona uno snapshot dal menu GRUB."
echo -e "   b) Verifica che tutto funzioni."
echo -e "   c) Apri il terminale e digita: ${BOLD}snapper rollback${NC}"
echo -e "   d) Riavvia per rendere la modifica permanente."
echo ""
