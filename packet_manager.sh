#!/bin/bash

# ==============================================================================
#  ARCH LINUX MAINTENANCE & AUR AUTOMATION
# ==============================================================================
#  Implementa le best practices per:
#  1. Installazione sicura di Paru (AUR Helper in Rust)
#  2. Configurazione Paru per usare Doas e Audit
#  3. Automazione pulizia cache pacchetti (Anti-Bit Rot)
# ==============================================================================

# --- CONFIGURAZIONE VISIVA ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_OK="[✔]"
ICON_KO="[✘]"
ICON_GEAR="[⚙]"
ICON_AUR="[⚓]"
ICON_BROOM="[🧹]"

# File di Log
LOG_FILE="maintenance_setup.log"

# --- RILEVAMENTO UTENTE ---
# Poiché lo script gira come root, dobbiamo sapere chi è l'utente "reale" per compilare AUR
REAL_USER=${SUDO_USER:-$USER}
HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)

if [[ "$REAL_USER" == "root" ]]; then
    echo -e "${RED}${ICON_KO} ERRORE: Non eseguire questo script direttamente da una shell di root pura.${NC}"
    echo -e "Eseguilo come utente normale usando sudo: ${BOLD}sudo ./maintenance_setup.sh${NC}"
    exit 1
fi

# --- FUNZIONI ---

log_header() {
    echo -e "\n${BLUE}${BOLD}:: $1${NC}"
}

log_success() {
    echo -e "${GREEN}${ICON_OK} $1${NC}"
}

log_info() {
    echo -e "${CYAN}${ICON_GEAR} $1${NC}"
}

check_pkg() {
    if ! pacman -Qi $1 &> /dev/null; then
        echo -e "${YELLOW}   Installazione dipendenza: $1...${NC}"
        pacman -S --noconfirm --needed $1 >> "$LOG_FILE" 2>&1
    else
        echo -e "${GREEN}${ICON_OK} Trovato: $1${NC}"
    fi
}

# --- LOGICA PRINCIPALE ---

clear
echo -e "${CYAN}${BOLD}"
echo "   _  _   _   ___  _  _  7. MANUTENZIONE "
echo "  | || | /_\ | _ \| || |  & LIFECYCLE    "
echo "  | __ |/ _ \|   /| __ |                 "
echo "  |_||_/_/ \_\_|_\ \_||_|  AUTOMATION    "
echo -e "${NC}"
echo -e "${BLUE}=============================================${NC}"
echo -e "Utente target per AUR: ${BOLD}$REAL_USER${NC}"
echo ""

# -----------------------------------------------------------
# 1. PREPARAZIONE AMBIENTE
# -----------------------------------------------------------
log_header "1. Verifica Dipendenze di Base"

# Aggiornamento database pacchetti
log_info "Aggiornamento database pacman..."
pacman -Sy >> "$LOG_FILE" 2>&1

# Installazione base-devel, git, rust (per paru) e opendoas (richiesto dalla guida)
check_pkg "base-devel"
check_pkg "git"
check_pkg "rust"      # Paru è scritto in Rust
check_pkg "opendoas"  # Richiesto dalla guida per sostituire sudo
check_pkg "pacman-contrib" # Contiene paccache

# -----------------------------------------------------------
# 2. INSTALLAZIONE PARU (AUR HELPER)
# -----------------------------------------------------------
log_header "2. Installazione Paru (Rust AUR Helper)"

if command -v paru &> /dev/null; then
    log_success "Paru è già installato."
else
    log_info "Clonazione e compilazione di Paru (può richiedere tempo)..."
    
    # Creazione directory temporanea come utente normale
    BUILD_DIR="$HOME_DIR/.tmp_paru_build"
    sudo -u "$REAL_USER" mkdir -p "$BUILD_DIR"
    
    # Clonazione
    if sudo -u "$REAL_USER" git clone https://aur.archlinux.org/paru.git "$BUILD_DIR"; then
        echo -e "   ${ICON_AUR} Sorgenti scaricati. Avvio compilazione..."
        
        # Compilazione (makepkg)
        cd "$BUILD_DIR" || exit
        if sudo -u "$REAL_USER" makepkg -si --noconfirm; then
            log_success "Paru installato con successo!"
        else
            echo -e "${RED}${ICON_KO} Compilazione fallita. Controlla $LOG_FILE${NC}"
            exit 1
        fi
        
        # Pulizia
        cd ..
        rm -rf "$BUILD_DIR"
    else
        echo -e "${RED}${ICON_KO} Impossibile clonare paru da AUR.${NC}"
        exit 1
    fi
fi

# -----------------------------------------------------------
# 3. CONFIGURAZIONE PARU (DOAS & AUDIT)
# -----------------------------------------------------------
log_header "3. Configurazione Paru (/etc/paru.conf)"

PARU_CONF="/etc/paru.conf"

if [[ -f "$PARU_CONF" ]]; then
    # Backup
    cp "$PARU_CONF" "$PARU_CONF.bak"
    
    # 1. Abilita Sudo = doas
    # Cerca la riga #Sudo = ... e la sostituisce, oppure la aggiunge se manca nella sezione [bin]
    if grep -q "#Sudo" "$PARU_CONF"; then
        sed -i 's/#Sudo = doas/Sudo = doas/' "$PARU_CONF"
        sed -i 's/#Sudo = sudo/Sudo = doas/' "$PARU_CONF" # Caso fallback
        log_success "Attivato Doas in Paru"
    else
        # Se non trova la riga commentata, controlliamo se è già attiva
        if grep -q "Sudo = doas" "$PARU_CONF"; then
             log_success "Doas già attivo in Paru"
        else
             echo "Sudo = doas" >> "$PARU_CONF"
             log_success "Aggiunto Doas in Paru"
        fi
    fi

    # 2. Ensure Review is enforced (Paru di default chiede, ma verifichiamo settings opzionali)
    # Solitamente 'BottomUp' è estetico, ma per la sicurezza ci affidiamo al default 'UpgradeMenu'
    # La guida dice "deve essere configurato per mostrare sempre il PKGBUILD".
    # In Paru questo è il default, ma sblocchiamo 'NewsOnUpgrade' per sicurezza informativa.
    sed -i 's/#NewsOnUpgrade/NewsOnUpgrade/' "$PARU_CONF"
    
    log_success "Configurazione Paru aggiornata."
else
    echo -e "${YELLOW}Attenzione: $PARU_CONF non trovato.${NC}"
fi

# Configurazione base di Doas se non esiste (per permettere a paru di funzionare)
if [[ ! -f "/etc/doas.conf" ]]; then
    log_info "Creazione configurazione minima /etc/doas.conf"
    echo "permit persist :wheel" > /etc/doas.conf
    chmod 600 /etc/doas.conf # Permessi sicuri obbligatori per doas
    log_success "Doas configurato (permit persist :wheel)"
fi


# -----------------------------------------------------------
# 4. IGIENE DEL SISTEMA (PACCACHE HOOK)
# -----------------------------------------------------------
log_header "4. Configurazione Hook di Pulizia Cache"

HOOK_DIR="/etc/pacman.d/hooks"
HOOK_FILE="$HOOK_DIR/paccache.hook"

# Crea directory se manca
mkdir -p "$HOOK_DIR"

log_info "Scrittura hook in $HOOK_FILE..."

cat <<EOF > "$HOOK_FILE"
[Trigger]
Operation = Remove
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Pulizia cache pacchetti (Keep Last 1)...
When = PostTransaction
Exec = /usr/bin/paccache -rk1
EOF

if [[ -f "$HOOK_FILE" ]]; then
    log_success "Hook creato. Il sistema manterrà solo 1 versione di backup."
    echo -e "   ${ICON_BROOM} Esecuzione pulizia iniziale..."
    paccache -rk1
else
    echo -e "${RED}${ICON_KO} Errore nella creazione dell'hook.${NC}"
fi

# -----------------------------------------------------------
# CONCLUSIONE
# -----------------------------------------------------------
echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}${BOLD}   MANUTENZIONE AUTOMATIZZATA COMPLETATA   ${NC}"
echo -e "${BLUE}=============================================${NC}"
echo -e "1. ${BOLD}Paru${NC} installato e configurato per usare ${BOLD}doas${NC}."
echo -e "2. ${BOLD}Paccache${NC} hook attivo (pulizia automatica post-aggiornamento)."
echo ""
echo -e "${YELLOW}${ICON_AUR} Nota:${NC} Ricorda di ispezionare sempre i PKGBUILD quando usi Paru."
echo -e "${YELLOW}${ICON_GEAR} Doas:${NC} Se è la prima volta che usi doas, verifica /etc/doas.conf."
echo ""
