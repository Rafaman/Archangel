#!/bin/bash

# ==============================================================================
#  SMART GPU & KERNEL DRIVER AUTOMATOR
# ==============================================================================
#  1. Rileva il Kernel in uso -> Installa gli Headers corretti
#  2. Rileva la GPU (NVIDIA/AMD/Intel) -> Installa i driver migliori
#  3. Gestione DKMS automatica per kernel custom (Zen/Hardened/LTS)
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_CPU="[🧠]"
ICON_GPU="[🎮]"
ICON_NVIDIA="[🟢]"
ICON_AMD="[🔴]"
ICON_INTEL="[🔵]"
ICON_DKMS="[🧱]"
ICON_WARN="[!]"

# --- FUNZIONI ---

log_header() { echo -e "\n${CYAN}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}[OK] $1${NC}"; }
log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_err() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then log_err "Esegui come root (sudo)."; fi
}

enable_multilib_check() {
    # Verifica se multilib è attivo (necessario per Steam/Giochi 32bit)
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${YELLOW}${ICON_WARN} Attenzione: repository [multilib] non attivo in pacman.conf.${NC}"
        echo -e "      I pacchetti lib32-* (necessari per il gaming) non verranno installati."
        sleep 2
        return 1
    fi
    return 0
}

# --- MAIN ---

clear
echo -e "${BLUE}${BOLD}"
echo "   ___  ___  _   _    ___  ____  _____ "
echo "  / __|| _ \| | | |  / _ \|_  / |_   _|"
echo " | (_ ||  _/| |_| | |  _/  / /    | |  "
echo "  \___||_|   \___/  |_|   /___|   |_|  "
echo "      DRIVER AUTOMATION SYSTEM         "
echo -e "${NC}"
echo -e "${BLUE}=======================================${NC}"

check_root
enable_multilib_check
HAS_MULTILIB=$? # 0 = attivo, 1 = inattivo

# ---------------------------------------------------------
# 1. RILEVAMENTO KERNEL E HEADERS
# ---------------------------------------------------------
log_header "1. Analisi Kernel e Installazione Headers"

CURRENT_KERNEL=$(uname -r)
KERNEL_PKG=""
HEADERS_PKG=""

echo -e "   ${ICON_CPU} Kernel in uso: ${BOLD}$CURRENT_KERNEL${NC}"

if [[ "$CURRENT_KERNEL" == *"zen"* ]]; then
    KERNEL_TYPE="Zen"
    HEADERS_PKG="linux-zen-headers"
elif [[ "$CURRENT_KERNEL" == *"lts"* ]]; then
    KERNEL_TYPE="LTS"
    HEADERS_PKG="linux-lts-headers"
elif [[ "$CURRENT_KERNEL" == *"hardened"* ]]; then
    KERNEL_TYPE="Hardened"
    HEADERS_PKG="linux-hardened-headers"
else
    KERNEL_TYPE="Standard"
    HEADERS_PKG="linux-headers"
fi

log_info "Tipo rilevato: $KERNEL_TYPE. Pacchetto richiesto: $HEADERS_PKG"

if pacman -Qi $HEADERS_PKG &> /dev/null; then
    log_success "Headers già installati."
else
    echo -e "   Installazione $HEADERS_PKG..."
    pacman -S --noconfirm --needed $HEADERS_PKG
    log_success "Headers installati (Pronto per DKMS)."
fi

# ---------------------------------------------------------
# 2. RILEVAMENTO GPU
# ---------------------------------------------------------
log_header "2. Rilevamento GPU"

GPU_INFO=$(lspci -k | grep -A 2 -E "(VGA|3D)")
echo -e "${CYAN}$GPU_INFO${NC}\n"

DRIVER_PACKAGES=""

# Logica di selezione
if echo "$GPU_INFO" | grep -qi "NVIDIA"; then
    # --- NVIDIA ---
    echo -e "   ${ICON_NVIDIA} Rilevata GPU NVIDIA."
    
    # Per Kernel custom (Zen) è OBBLIGATORIO usare nvidia-dkms
    DRIVER_PACKAGES="nvidia-dkms nvidia-utils nvidia-settings opencl-nvidia"
    
    if [ $HAS_MULTILIB -eq 0 ]; then
        DRIVER_PACKAGES="$DRIVER_PACKAGES lib32-nvidia-utils lib32-opencl-nvidia"
    fi
    
    # Check per schede vecchissime (Kepler/Fermi) che non supportano driver nuovi
    # Questo è un check euristico semplice
    if echo "$GPU_INFO" | grep -Eiq "GTX (6|7)[0-9][0-9]|GT (6|7)[0-9][0-9]"; then
        echo -e "${YELLOW}${ICON_WARN} ATTENZIONE: Potresti avere una scheda NVIDIA Legacy.${NC}"
        echo -e "      I driver attuali supportano solo Maxwell (serie 900) e superiori."
        echo -e "      Se hai una scheda vecchia, interrompi e usa i driver AUR (nvidia-470xx-dkms)."
        echo -n "      Continuare con l'installazione dei driver moderni? [y/N]: "
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then exit 0; fi
    fi

elif echo "$GPU_INFO" | grep -qi "Advanced Micro Devices"; then
    # --- AMD ---
    echo -e "   ${ICON_AMD} Rilevata GPU AMD (Radeon)."
    # Driver open source Mesa (Migliori per AMD su Linux)
    DRIVER_PACKAGES="mesa vulkan-radeon xf86-video-amdgpu"
    
    if [ $HAS_MULTILIB -eq 0 ]; then
        DRIVER_PACKAGES="$DRIVER_PACKAGES lib32-mesa lib32-vulkan-radeon"
    fi

elif echo "$GPU_INFO" | grep -qi "Intel"; then
    # --- INTEL ---
    echo -e "   ${ICON_INTEL} Rilevata GPU Intel (iGPU/Arc)."
    DRIVER_PACKAGES="mesa vulkan-intel intel-media-driver"
    
    if [ $HAS_MULTILIB -eq 0 ]; then
        DRIVER_PACKAGES="$DRIVER_PACKAGES lib32-mesa lib32-vulkan-intel"
    fi
    
else
    # --- VM / ALTRO ---
    echo -e "${YELLOW}Nessuna GPU standard rilevata (VMWare/VirtualBox?).${NC}"
    echo -e "Installazione driver generici Mesa."
    DRIVER_PACKAGES="mesa"
fi

# ---------------------------------------------------------
# 3. INSTALLAZIONE DRIVER
# ---------------------------------------------------------
log_header "3. Installazione Pacchetti Driver"

if [ -z "$DRIVER_PACKAGES" ]; then
    log_err "Nessun pacchetto selezionato."
else
    echo -e "   Pacchetti target: ${BOLD}$DRIVER_PACKAGES${NC}"
    pacman -S --needed --noconfirm $DRIVER_PACKAGES
    log_success "Installazione completata."
fi

echo ""
echo -e "${BLUE}=======================================${NC}"
echo -e "${GREEN}${BOLD}   SETUP GRAFICO COMPLETATO   ${NC}"
echo -e "${BLUE}=======================================${NC}"
echo -e "Riavvia il sistema per caricare i nuovi moduli kernel."
echo ""
