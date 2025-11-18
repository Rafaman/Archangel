#!/bin/bash

# =============================================================================
# ARCH LINUX SECURITY HARDENING - LEVEL 4: NETWORK (FW & DNS)
# =============================================================================
# Reference: Guida Operativa 3.4
# Description: Configurazione UFW (Firewall) e systemd-resolved (DNS over TLS).
# =============================================================================

# --- Configurazioni Estetiche ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BOLD}${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${BOLD}${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${BOLD}${YELLOW}[WARN]${NC} $1"; }
log_prompt() { echo -e "${BOLD}${CYAN}[?]${NC} $1"; }
log_err() { echo -e "${BOLD}${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "   _   _  _____  _____  _    _  _____ ______  _   __"
    echo "  | \ | ||  ___||_   _|| |  | ||  _  || ___ \| | / /"
    echo "  |  \| || |__    | |  | |  | || | | || |_/ /| |/ / "
    echo "  | . \` ||  __|   | |  | |/\| || | | ||    / |    \ "
    echo "  | |\  || |___   | |  \  /\  /\ \_/ /| |\ \ | |\  \\"
    echo "  \_| \_/\____/   \_/   \/  \/  \___/ \_| \_|\_| \_/"
    echo -e "      FIREWALL & DNS OVER TLS SETUP${NC}"
    echo ""
    echo "Configurazione UFW e systemd-resolved secondo guida 3.4"
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

echo -n "Vuoi procedere con l'hardening di Rete? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_err "Annullato."
fi

# =============================================================================
# PARTE 1: FIREWALL (UFW)
# =============================================================================
echo ""
log_info "--- FASE 1: Configurazione UFW ---"

# 1. Installazione
if ! pacman -Qi ufw &>/dev/null; then
    log_info "Installazione pacchetto UFW..."
    pacman -S --noconfirm --needed ufw || log_err "Installazione UFW fallita"
else
    log_success "UFW è già installato."
fi

# 2. Configurazione Default (Guida: deny incoming, allow outgoing)
log_info "Applicazione policy di base..."
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
log_success "Policy: Deny Incoming / Allow Outgoing applicate."

# 3. Configurazione Opzionale (SSH)
log_prompt "Hai bisogno di accedere a questo PC via SSH dall'esterno? [y/N]"
read ssh_req
if [[ "$ssh_req" =~ ^[Yy]$ ]]; then
    # Guida: ufw limit ssh
    ufw limit ssh >/dev/null
    log_success "SSH consentito (con rate-limiting anti brute-force)."
else
    log_info "SSH non abilitato (massima sicurezza)."
fi

# 4. Configurazione Opzionale (LAN)
log_prompt "Vuoi permettere connessioni dalla tua rete locale (192.168.0.x)? [y/N]"
echo -e "   ${YELLOW}(Utile per stampanti di rete, condivisione file, KDE Connect)${NC}"
read lan_req
if [[ "$lan_req" =~ ^[Yy]$ ]]; then
    # Guida: ufw allow from 192.168.0.0/24
    # Nota: Assumiamo una subnet standard /24.
    ufw allow from 192.168.0.0/24 >/dev/null
    log_success "Traffico LAN (192.168.0.0/24) consentito."
fi

# 5. Attivazione
log_info "Attivazione Firewall..."
# Usiamo --force per evitare il prompt di conferma interruzione SSH (se attivo)
ufw --force enable
systemctl enable --now ufw.service
log_success "UFW Attivo e Abilitato."

# =============================================================================
# PARTE 2: DNS CRITTOGRAFATO (systemd-resolved)
# =============================================================================
echo ""
log_info "--- FASE 2: DNS over TLS (systemd-resolved) ---"

RESOLVED_CONF_DIR="/etc/systemd/resolved.conf.d"
RESOLVED_CONF_FILE="$RESOLVED_CONF_DIR/99-secure-dns.conf"

# 1. Creazione Directory e File
if [ ! -d "$RESOLVED_CONF_DIR" ]; then
    mkdir -p "$RESOLVED_CONF_DIR"
fi

log_info "Scrittura configurazione in $RESOLVED_CONF_FILE..."

# Nota: Aggiungiamo [Resolve] perché è richiesto dalla sintassi systemd,
# anche se la guida da te incollata mostrava solo le chiavi.
cat <<EOF > "$RESOLVED_CONF_FILE"
[Resolve]
# Guida 3.4: Quad9 (Secure) + Cloudflare (Speed)
# La sintassi IP#Hostname forza la validazione TLS
DNS=9.9.9.9#dns.quad9.net 1.1.1.1#cloudflare-dns.com

# Fallback (Google)
FallbackDNS=8.8.8.8#dns.google

# Hardening DNS
DNSOverTLS=yes
DNSSEC=yes
EOF

log_success "Configurazione DoT scritta."

# 2. Riavvio e Link Simbolico
log_info "Riavvio systemd-resolved..."
systemctl enable --now systemd-resolved.service
systemctl restart systemd-resolved.service

# Controllo Link Simbolico (Best Practice Arch)
# Affinché le applicazioni usino systemd-resolved, /etc/resolv.conf deve essere un link
if [[ "$(readlink /etc/resolv.conf)" != *"/run/systemd/resolve/stub-resolv.conf"* ]]; then
    log_warn "/etc/resolv.conf non punta al resolver di systemd."
    log_prompt "Vuoi correggere il link simbolico ora? (Consigliato) [y/N]"
    read link_req
    if [[ "$link_req" =~ ^[Yy]$ ]]; then
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        log_success "Link simbolico aggiornato."
    fi
fi

# =============================================================================
# VERIFICA FINALE
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}SETUP COMPLETATO!${NC}"
echo "-----------------------------------------------------"
echo -e "${BOLD}Stato Firewall:${NC}"
ufw status verbose | head -n 5
echo "..."
echo ""
echo -e "${BOLD}Stato DNS over TLS:${NC}"
# Controllo rapido se siamo in modalità +Enc (Encrypted)
resolvectl status | grep "DNSOverTLS" | head -n 1
echo "-----------------------------------------------------"
echo "Ora navighi protetto da Firewall e DNS criptato."
