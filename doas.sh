#!/bin/bash

# ==============================================================================
#  PRIVILEGE HARDENING: DOAS MIGRATION
# ==============================================================================
#  1. Installazione e Configurazione OpenDoas
#  2. Integrazione con Makepkg (PACMAN_AUTH)
#  3. Creazione symlink di compatibilità (sudo -> doas)
#  4. Disabilitazione account Root (Lock)
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

ICON_LOCK="[🔒]"
ICON_KEY="[🔑]"
ICON_skull="[💀]"
ICON_CHECK="[✔]"
ICON_WARN="[!]"

# --- VARIABILI & UTENTE ---
REAL_USER=${SUDO_USER:-$USER}
DOAS_CONF="/etc/doas.conf"
MAKEPKG_CONF="/etc/makepkg.conf"

# --- FUNZIONI ---

log_step() {
    echo -e "\n${PURPLE}${BOLD}:: $1${NC}"
}

log_success() {
    echo -e "${GREEN}${ICON_CHECK} $1${NC}"
}

log_error() {
    echo -e "${RED}${ICON_skull} ERRORE CRITICO: $1${NC}"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo attuale).${NC}"
       exit 1
    fi
}

# --- LOGICA PRINCIPALE ---

clear
echo -e "${BLUE}${BOLD}"
echo "   ___  ___   _   ___ "
echo "  |   \/ _ \ /_\ / __|"
echo "  | |) | (_) / _ \\__ \\"
echo "  |___/ \___/_/ \_\___/ MIGRATION TOOL"
echo -e "${NC}"
echo -e "${BLUE}======================================${NC}"

check_root

# 1. VERIFICA DI SICUREZZA PRELIMINARE
# Se l'utente non è in wheel e disabilitiamo root, il sistema è inaccessibile.
log_step "Verifica Gruppo Wheel"
if groups "$REAL_USER" | grep -q "\bwheel\b"; then
    log_success "L'utente $REAL_USER fa parte del gruppo 'wheel'. Procedo."
else
    log_error "L'utente $REAL_USER NON è nel gruppo 'wheel'. Aggiungilo prima di continuare (usermod -aG wheel $REAL_USER)."
fi

# 2. INSTALLAZIONE OPENDOAS
log_step "Installazione opendoas"
if ! pacman -Qi opendoas &> /dev/null; then
    pacman -S --noconfirm opendoas
    log_success "Opendoas installato."
else
    log_success "Opendoas già presente."
fi

# 3. CONFIGURAZIONE /etc/doas.conf
log_step "Configurazione regole ($DOAS_CONF)"

# Scriviamo la regola: permit persist :wheel as root
# persist: ricorda la password per un po' (come sudo timestamp)
echo "permit persist :wheel as root" > "$DOAS_CONF"

# Controllo permessi (CRITICO: doas rifiuta di funzionare se il file non è sicuro)
chmod 0600 "$DOAS_CONF"
chown root:root "$DOAS_CONF"

if [[ -f "$DOAS_CONF" ]]; then
    log_success "Configurazione scritta e permessi (0600) impostati."
    echo -e "${BOLD}   Contenuto:${NC} $(cat $DOAS_CONF)"
fi

# Test rapido configurazione
if doas -C "$DOAS_CONF"; then
    log_success "Sintassi file di configurazione valida."
else
    log_error "Sintassi doas.conf non valida!"
fi

# 4. INTEGRAZIONE MAKEPKG
log_step "Configurazione Makepkg (PACMAN_AUTH)"

# Cerca la riga PACMAN_AUTH e la imposta su (doas)
# Se è commentata (#PACMAN_AUTH), la scommenta e modifica.
if grep -q "PACMAN_AUTH" "$MAKEPKG_CONF"; then
    sed -i 's/^#PACMAN_AUTH=.*/PACMAN_AUTH=(doas)/' "$MAKEPKG_CONF"
    sed -i 's/^PACMAN_AUTH=.*/PACMAN_AUTH=(doas)/' "$MAKEPKG_CONF"
    log_success "Impostato PACMAN_AUTH=(doas) in $MAKEPKG_CONF"
else
    echo "PACMAN_AUTH=(doas)" >> "$MAKEPKG_CONF"
    log_success "Aggiunto PACMAN_AUTH=(doas) in fondo a $MAKEPKG_CONF"
fi

# 5. GESTIONE SUDO (SHIM O RIMOZIONE)
log_step "Gestione binario 'sudo'"

echo -e "${YELLOW}Vuoi rimuovere il pacchetto originale 'sudo' e creare un symlink?${NC}"
echo -e "Questo garantisce che gli script che invocano 'sudo' usino 'doas' invece."
echo -e -n "${BOLD}(s/N): ${NC}"
read -r choice

if [[ "$choice" =~ ^([sS][iI]|[sS])$ ]]; then
    echo -e "   Rimozione sudo..."
    # Rimuove sudo, ma non le dipendenze che potrebbero rompere il sistema (base-devel dipende da sudo a volte)
    # Usiamo -Rdd per forzare la rimozione rompendo la dipendenza di base-devel, che soddisferemo col symlink
    pacman -Rdd --noconfirm sudo
    
    echo -e "   Creazione symlink /usr/bin/sudo -> /usr/bin/doas..."
    ln -s /usr/bin/doas /usr/bin/sudo
    
    log_success "Sudo rimpiazzato da symlink a Doas."
else
    echo -e "${YELLOW}Sudo mantenuto. Ricorda di usare 'doas' manualmente.${NC}"
    # Creazione alias per l'utente (opzionale, in .bashrc o .zshrc)
    USER_SHELL=$(getent passwd "$REAL_USER" | cut -d: -f7)
    RC_FILE="$HOME_DIR/.bashrc"
    [[ "$USER_SHELL" == *"zsh"* ]] && RC_FILE="$HOME_DIR/.zshrc"
    
    if ! grep -q "alias sudo='doas'" "$RC_FILE"; then
        echo "alias sudo='doas'" >> "$RC_FILE"
        echo "alias root='doas -s'" >> "$RC_FILE"
        chown "$REAL_USER" "$RC_FILE" 2>/dev/null
        log_success "Alias aggiunti a $RC_FILE per comodità."
    fi
fi

# 6. DISABILITAZIONE ROOT
log_step "Disabilitazione Account Root"
echo -e "${RED}${BOLD}${ICON_LOCK} ATTENZIONE:${NC} Stiamo per bloccare la password di root."
echo -e "L'unico modo per ottenere privilegi sarà tramite il tuo utente ($REAL_USER) via doas."

# Doppio controllo prima del lock
if groups "$REAL_USER" | grep -q wheel; then
    passwd -l root
    log_success "Password di root bloccata (Lock)."
else
    log_error "Qualcosa è cambiato nei gruppi utente. Abortito per sicurezza."
fi

# Verifica finale funzionamento doas
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}${BOLD}   MIGRAZIONE COMPLETATA   ${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "Per testare, apri un nuovo terminale e digita:"
echo -e "   ${BOLD}doas ls /root${NC}"
echo ""
