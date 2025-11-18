#!/bin/bash

# =============================================================================
# ARCH LINUX DESKTOP SETUP - SECTION 5.2: KDE PLASMA (CUSTOM)
# =============================================================================
# Reference: Guida Operativa 5.2 (Modificata)
# Description: Installa KDE Plasma Minimal con Alacritty come terminale.
# Target: plasma-desktop, alacritty, dolphin, sddm
# =============================================================================

# --- Configurazioni Estetiche ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BOLD}${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${BOLD}${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${BOLD}${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BOLD}${MAGENTA}[STEP]${NC} $1"; }
log_err() { echo -e "${BOLD}${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "   _  __ ____  _____  ____  _                   "
    echo "  | |/ /|  _ \| ____||  _ \| | __ _  ___ _ __ ___  __ _ "
    echo "  | ' / | | | |  _|  | |_) | |/ _\` |/ __| '_ \` _ \/ _\` |"
    echo "  | . \ | |_| | |___ |  __/| | (_| | (__| | | | | | (_| |"
    echo "  |_|\_\|____/|_____||_|   |_|\__,_|\___|_| |_| |_|\__,_|"
    echo -e "      MINIMAL INSTALLATION (Alacritty Edition)${NC}"
    echo ""
    echo "Stai per installare KDE Plasma Desktop (Core)."
    echo "Terminale scelto: ALACRITTY"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "Serve root (o doas!)."
    fi
}

# --- Main Logic ---

banner
check_root

echo -n "Vuoi procedere con l'installazione? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_err "Annullato."
fi

# 1. Aggiornamento Database
log_step "Aggiornamento database pacchetti..."
pacman -Sy || log_warn "Impossibile aggiornare i database, provo comunque l'installazione..."

# 2. Installazione Pacchetti
log_step "Installazione componenti core..."
# plasma-desktop: Core desktop
# alacritty: Terminale (GPU accelerated, minimal)
# dolphin: File Manager
# sddm: Login Manager
PACKAGES="plasma-desktop alacritty dolphin sddm"

log_info "Scaricamento e installazione di: $PACKAGES"
pacman -S --noconfirm --needed $PACKAGES || log_err "Installazione fallita."
log_success "Pacchetti installati."

# 3. Abilitazione SDDM
log_step "Configurazione Display Manager (SDDM)..."
# SDDM è il servizio che fornisce la schermata di login grafica
systemctl enable sddm.service || log_err "Impossibile abilitare sddm."
log_success "SDDM abilitato (partirà al prossimo avvio)."

# 4. Verifica Wayland
log_step "Verifica sessione..."
if [ -f /usr/share/wayland-sessions/plasma.desktop ]; then
    log_info "Sessione Plasma Wayland pronta."
fi

# 5. Note Post-Installazione
echo ""
echo -e "${BOLD}${GREEN}INSTALLAZIONE COMPLETATA!${NC}"
echo "-----------------------------------------------------"
echo -e "${BOLD}Note Specifiche per Alacritty:${NC}"
echo "1. Alacritty non ha menu grafici. Si configura tramite file:"
echo "   ~/.config/alacritty/alacritty.toml (o .yml nelle vecchie versioni)"
echo "2. Non supporta nativamente il pannello F4 integrato dentro Dolphin"
echo "   (funzionalità specifica di Konsole)."
echo ""
echo -e "${BOLD}Note di Sistema:${NC}"
echo "- Ricorda di installare 'pipewire' per l'audio e 'plasma-nm' per il WiFi"
echo "  se non lo hai già fatto."
echo "-----------------------------------------------------"
echo "Riavvia il sistema: reboot"
