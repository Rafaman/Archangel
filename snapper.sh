#!/bin/bash

# =============================================================================
# ARCH LINUX SNAPPER & SNAP-PAC SETUP (LIMINE EDITION)
# =============================================================================
# Reference: Guida Operativa 2.3, 2.4 (Adattata per Limine)
# Description: Configura snapshot automatici su layout Btrfs Flat.
# =============================================================================

# --- Configurazioni Estetiche ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BOLD}${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${BOLD}${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${BOLD}${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${BOLD}${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    clear
    echo -e "${BOLD}${GREEN}"
    echo "   _____  _   _  ___  ______ ______  ___________ "
    echo "  /  ___|| \ | |/ _ \ | ___ \| ___ \|  ___| ___ \\"
    echo "  \ \`--. |  \| / /_\ \| |_/ /| |_/ /| |__ | |_/ /"
    echo "   \`--. \| . \` |  _  ||  __/ |  __/ |  __||    / "
    echo "  /\__/ /| |\  | | | || |    | |    | |___| |\ \ "
    echo "  \____/ \_| \_/\_| |_/\_|    \_|    \____/\_| \_| "
    echo -e "         SETUP FOR LIMINE & FLAT LAYOUT${NC}"
    echo ""
    echo "Questo script configurerà Snapper e Snap-pac."
    echo "Poiché usi Limine, 'grub-btrfs' verrà ESCLUSO."
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "Devi eseguire lo script come root."
    fi
}

# --- Main Logic ---

banner
check_root

echo -n "Vuoi procedere con la configurazione di Snapper? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_err "Annullato."
fi

# 1. Installazione Pacchetti (Senza grub-btrfs)
log_info "Installazione pacchetti necessari..."
# Installiamo solo snapper e snap-pac.
# grub-btrfs è inutile per Limine e causerebbe errori se non trova grub.cfg
pacman -S --noconfirm --needed snapper snap-pac || log_err "Installazione fallita."
log_success "Pacchetti installati (Snapper, Snap-pac)."

# 2. Configurazione Snapper per la ROOT
log_info "Configurazione Snapper per la Root (/)..."

# --- FIX CRITICO PER LAYOUT FLAT ---
# Snapper create-config prova a creare un subvolume .snapshots dentro /.
# Ma noi abbiamo già montato @snapshots in /.snapshots tramite fstab.
# Dobbiamo smontarlo temporaneamente per permettere a Snapper di configurarsi,
# poi cancellare la cartella creata da Snapper e rimontare il nostro subvolume.

if mountpoint -q /.snapshots; then
    log_info "Smontaggio temporaneo di /.snapshots per configurazione..."
    umount /.snapshots || log_err "Impossibile smontare /.snapshots"
fi

# Rimuoviamo la directory se esiste (deve essere vuota/inesistente per create-config)
if [ -d "/.snapshots" ]; then
    rm -rf /.snapshots
fi

# Creazione configurazione
log_info "Esecuzione snapper create-config..."
snapper -c root create-config / || log_err "Creazione config root fallita"

# Ora Snapper ha creato un subvolume annidato in /.snapshots. Lo eliminiamo.
log_info "Ripristino mountpoint @snapshots (Layout Flat)..."
btrfs subvolume delete /.snapshots &>/dev/null || rm -rf /.snapshots
mkdir /.snapshots

# Rimontiamo tutto usando fstab (che contiene la riga corretta per @snapshots)
mount -a || log_err "Errore nel rimontare i volumi (controlla fstab!)"

# Verifica
if mountpoint -q /.snapshots; then
    log_success "Configurazione root completata e @snapshots rimontato correttamente."
else
    log_err "/.snapshots non risulta montato correttamente dopo l'operazione."
fi

# 3. Regolazione Permessi (Sezione 2.3 Guida)
log_info "Impostazione permessi per lettura snapshot utente..."
chmod a+rx /.snapshots
# Assegniamo al gruppo users (o wheel se preferisci)
chown :users /.snapshots
log_success "Permessi /.snapshots aggiornati."

# 4. Configurazione Opzionale per /home
echo ""
echo -n "Vuoi configurare gli snapshot anche per /home? [y/N]: "
read conf_home
if [[ "$conf_home" =~ ^[Yy]$ ]]; then
    log_info "Configurazione Snapper per /home..."
    snapper -c home create-config /home || log_warn "Configurazione home fallita (forse già esistente?)"
    
    # Ottimizzazione retention policy per home (meno snapshot per risparmiare spazio)
    snapper -c home set-config TIMELINE_LIMIT_HOURLY="5"
    snapper -c home set-config TIMELINE_LIMIT_DAILY="7"
    snapper -c home set-config TIMELINE_LIMIT_WEEKLY="0"
    snapper -c home set-config TIMELINE_LIMIT_MONTHLY="0"
    snapper -c home set-config TIMELINE_LIMIT_YEARLY="0"
    log_success "Configurazione /home completata."
fi

# 5. Configurazione Retention Policy (Sistema)
# Riduciamo i default per evitare di riempire il disco troppo in fretta
log_info "Ottimizzazione policy di ritenzione snapshot (Root)..."
snapper -c root set-config TIMELINE_LIMIT_HOURLY="5"
snapper -c root set-config TIMELINE_LIMIT_DAILY="7"
snapper -c root set-config TIMELINE_LIMIT_WEEKLY="2"
snapper -c root set-config TIMELINE_LIMIT_MONTHLY="0"
snapper -c root set-config TIMELINE_LIMIT_YEARLY="0"
# Abilita cleanup background
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer
log_success "Policy applicate e timer attivati."

# 6. Integrazione Bootloader (LIMINE SPECIFIC)
echo ""
echo -e "${BOLD}${YELLOW}--- ATTENZIONE: INTEGRAZIONE BOOTLOADER ---${NC}"
echo "La guida originale prevede 'grub-btrfs', che non funziona con Limine."
echo "Gli snapshot verranno creati automaticamente (grazie a snap-pac) prima/dopo"
echo "ogni installazione con pacman, MA non appariranno automaticamente nel menu di boot."

log_info "Verifica creazione snapshot iniziale..."
snapper -c root create --description "Configurazione Iniziale Post-Script"
snapper ls | grep "Configurazione Iniziale" && log_success "Snapshot di prova creato con successo!"

echo ""
echo -e "${BOLD}${GREEN}SETUP COMPLETATO!${NC}"
echo "-----------------------------------------------------"
echo "1. Gli snapshot automatici sono ATTIVI (snap-pac)."
echo "2. Puoi gestire gli snapshot con: 'snapper list', 'snapper rollback'."
echo "3. Per avviare dagli snapshot con Limine, hai due opzioni:"
echo "   A) Installare 'limine-snapper-sync' (disponibile su AUR)."
echo "      (Consigliato se vuoi un menu automatico simile a GRUB)."
echo "   B) Usare Limine manualmente editando limine.conf in caso di emergenza."
echo "-----------------------------------------------------"
