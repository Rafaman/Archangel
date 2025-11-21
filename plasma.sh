#!/bin/bash

# ==============================================================================
#  MINIMAL KDE PLASMA INSTALLER (WAYLAND FOCUSED)
# ==============================================================================
#  Installa un ambiente Plasma "chirurgico" senza bloatware.
#  Target: Wayland Session, Alacritty, Dolphin, SDDM.
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

ICON_PLASMA="[🖌️]"
ICON_APP="[🚀]"
ICON_WAYLAND="[💎]"
ICON_GEAR="[⚙]"
ICON_CHECK="[✔]"

# --- LISTE PACCHETTI ---

# 1. IL CUORE (No plasma-meta)
CORE_PKGS=(
    "plasma-desktop"   # Shell e KWin
    "sddm"             # Display Manager
    "wayland"          # Protocollo base
    "egl-wayland"      # Essenziale per NVIDIA (male non fa sugli altri)
    "xdg-desktop-portal-kde" # Fondamentale per Screen Sharing / Flatpak in Wayland
)

# 2. I MODULI FUNZIONALI (Spesso dimenticati nelle install minimali)
# Senza questi, non hai icona wifi, batteria o volume.
FUNCTIONAL_PKGS=(
    "powerdevil"       # Gestione energia (sospensione, luminosità)
    "kscreen"          # Gestione multi-monitor e risoluzione
    "plasma-nm"        # Applet NetworkManager (Wi-Fi UI)
    "plasma-pa"        # Applet PulseAudio/Pipewire (Volume UI)
    "bluedevil"        # Gestione Bluetooth (Rimuovi se non usi BT)
    "breeze"           # Tema base (per coerenza visiva SDDM)
    "breeze-gtk"       # Coerenza per app GTK/Gnome
)

# 3. LE APPLICAZIONI RICHIESTE
APP_PKGS=(
    "dolphin"          # File Manager
    "alacritty"        # Terminale (GPU Accelerated)
    "ffmpegthumbs"     # Thumbnail video per Dolphin
)

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

install_list() {
    local list_name=$1
    shift
    local pkgs=("$@")
    
    echo -e "   Installazione $list_name..."
    # --needed salta i pacchetti già aggiornati
    if pacman -S --needed --noconfirm "${pkgs[@]}"; then
        log_success "$list_name installati."
    else
        echo -e "${RED}Errore durante l'installazione di $list_name.${NC}"
        exit 1
    fi
}

# --- MAIN ---

clear
echo -e "${BLUE}${BOLD}"
echo "   _  _____  ___   ___  _    _   ___ __  __   _   "
echo "  | |/ /   \| __| | _ \| |  /_\ / __|  \/  | /_\  "
echo "  | ' <| |) | _|  |  _/| |_/ _ \\__ \ |\/| |/ _ \ "
echo "  |_|\_\___/|___| |_|  |___/_/ \_\___/_|  |_/_/ \_\\"
echo "         MINIMAL WAYLAND EDITION 2025             "
echo -e "${NC}"
echo -e "${BLUE}==================================================${NC}"

check_root

# 1. Aggiornamento preventivo
log_header "1. Preparazione Sistema"
log_info "Aggiornamento database pacman..."
pacman -Sy

# 2. Installazione Core Plasma
log_header "2. Installazione Core Plasma (Wayland Native)"
install_list "Core Components" "${CORE_PKGS[@]}"

# 3. Installazione Moduli Funzionali
log_header "3. Integrazione Moduli Hardware"
log_info "Installazione gestori Energia, Rete, Audio..."
install_list "Functional Modules" "${FUNCTIONAL_PKGS[@]}"

# 4. Installazione Applicazioni
log_header "4. Applicazioni Utente"
install_list "User Apps" "${APP_PKGS[@]}"

# 5. Configurazione SDDM
log_header "5. Configurazione Display Manager (SDDM)"

# Abilitazione servizio
systemctl enable sddm --now &> /dev/null
if systemctl is-enabled sddm &> /dev/null; then
    log_success "SDDM abilitato all'avvio."
else
    echo -e "${YELLOW}Attenzione: Impossibile abilitare sddm automaticamente.${NC}"
fi

# Creazione config per tema Breeze (estetica migliore del default)
# SDDM di default è molto spartano. Forziamo il tema Breeze se presente.
mkdir -p /etc/sddm.conf.d
echo "[Theme]
Current=breeze" > /etc/sddm.conf.d/kde_settings.conf
log_success "Tema SDDM impostato su 'breeze'."

# 6. Configurazione Alacritty (Opzionale)
# Alacritty non ha una config di default e appare brutto/basico senza.
# Verifichiamo se l'utente reale ha una config, altrimenti suggeriamo.
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

if [[ ! -d "$USER_HOME/.config/alacritty" ]]; then
    echo -e "${YELLOW}${ICON_APP} Nota: Alacritty non ha un file di configurazione.${NC}"
    echo -e "      Ti consiglio di copiarne uno base in ~/.config/alacritty/alacritty.toml"
fi

# 7. CONCLUSIONE
echo ""
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}${BOLD}   AMBIENTE DESKTOP PRONTO   ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Componenti installati:"
echo -e " - ${BOLD}Plasma Desktop${NC} (No bloat)"
echo -e " - ${BOLD}KWin Wayland${NC} (Compositor sicuro)"
echo -e " - ${BOLD}Dolphin & Alacritty${NC}"
echo -e " - ${BOLD}SDDM${NC} (Login Manager)"
echo ""
echo -e "${BOLD}Prossimo passo:${NC} Riavvia il sistema per accedere all'ambiente grafico."
echo -e "Comando: ${GREEN}reboot${NC}"
echo ""
