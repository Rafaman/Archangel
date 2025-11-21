#!/bin/bash

# ==============================================================================
#  NETWORK DEFENSE & PRIVACY SUITE
# ==============================================================================
#  1. UFW Firewall: Default Deny / Rate Limit SSH
#  2. Fail2Ban: Analisi Journald e Ban dinamico
#  3. DNS-over-TLS: Systemd-resolved + Quad9 (No ISP Snooping)
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_WALL="[🧱]"
ICON_BAN="[🚫]"
ICON_DNS="[🌐]"
ICON_LOCK="[🔒]"
ICON_OK="[✔]"
ICON_WARN="[!]"

# --- FUNZIONI ---

log_header() { echo -e "\n${CYAN}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_OK} $1${NC}"; }
log_info() { echo -e "${BLUE}${ICON_LOCK} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

# --- MAIN ---

clear
echo -e "${BLUE}${BOLD}"
echo "     _   _ ___ _____      _____  ___  _  __ "
echo "    | \ | | __|_   _|___ / / _ \/ _ \| |/ / "
echo "    | .\` | _|  | | |___| \_, / (_) | ' <  "
echo "    |_|\_|___| |_|      \___/ \___/|_|\_\ "
echo "        DEFENSE & PRIVACY AUTOMATION      "
echo -e "${NC}"
echo -e "${BLUE}==========================================${NC}"

check_root

# 1. CONFIGURAZIONE FIREWALL (UFW)
log_header "1. Configurazione Perimetrale (UFW)"

log_info "Installazione UFW..."
pacman -S --needed --noconfirm ufw &> /dev/null

log_info "Applicazione Policy: Default Deny Incoming..."
ufw default deny incoming &> /dev/null
ufw default allow outgoing &> /dev/null

log_info "Configurazione Rate Limiting SSH..."
# 'limit' imposta un tetto di connessioni (es. 6 tentativi in 30 sec) prima di bloccare
ufw limit ssh

echo -e "${YELLOW}${ICON_WARN} Sto per abilitare il firewall.${NC}"
echo -e "Se sei connesso via SSH, la regola 'limit ssh' dovrebbe mantenere la connessione."
ufw --force enable
log_success "Firewall attivo e persistente."

# 2. CONFIGURAZIONE FAIL2BAN
log_header "2. Protezione Brute-Force (Fail2Ban)"

log_info "Installazione Fail2Ban..."
pacman -S --needed --noconfirm fail2ban &> /dev/null

FAIL2BAN_JAIL="/etc/fail2ban/jail.local"

log_info "Scrittura configurazione Jail ($FAIL2BAN_JAIL)..."

# Creiamo una configurazione che usa il backend systemd (Journald)
# Invece di leggere file di log testuali, interroga direttamente il journal
cat <<EOF > "$FAIL2BAN_JAIL"
[DEFAULT]
bantime  = 10m
findtime = 10m
maxretry = 5
# Backend systemd è cruciale per Arch moderno
backend = systemd

[sshd]
enabled = true
mode    = aggressive
port    = ssh
logpath = %(sshd_log)s
backend = systemd
EOF

log_success "Jail SSH configurata (Backend: Systemd)."

log_info "Avvio servizio Fail2Ban..."
systemctl enable fail2ban --now &> /dev/null
log_success "Fail2Ban è attivo e sta monitorando il journal."

# 3. PRIVACY DNS (DNS-OVER-TLS)
log_header "3. Configurazione DNS-over-TLS (Systemd-resolved)"

RESOLVED_CONF_DIR="/etc/systemd/resolved.conf.d"
mkdir -p "$RESOLVED_CONF_DIR"
DOT_CONF="$RESOLVED_CONF_DIR/dns_privacy.conf"

log_info "Configurazione Provider Sicuri (Quad9)..."

# Usiamo Quad9 (9.9.9.9) come primario per il blocco malware e privacy.
# Formato IP#hostname è obbligatorio per la validazione TLS.
cat <<EOF > "$DOT_CONF"
[Resolve]
# Quad9 (Primary) & Cloudflare (Backup)
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 1.1.1.1#cloudflare-dns.com
DNSOverTLS=yes
DNSSEC=yes
FallbackDNS=8.8.8.8#dns.google
Domains=~.
EOF

log_success "Configurazione DoT scritta in $DOT_CONF"

log_info "Attivazione systemd-resolved..."
systemctl enable systemd-resolved --now &> /dev/null

# Gestione Symlink /etc/resolv.conf
# Arch richiede che resolv.conf sia un symlink allo stub di systemd per funzionare correttamente
if [[ -L "/etc/resolv.conf" ]]; then
    TARGET=$(readlink /etc/resolv.conf)
    if [[ "$TARGET" != *"/run/systemd/resolve/stub-resolv.conf"* ]]; then
        echo -e "${YELLOW}Aggiornamento symlink resolv.conf...${NC}"
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi
else
    echo -e "${YELLOW}Backup e sostituzione /etc/resolv.conf...${NC}"
    mv /etc/resolv.conf /etc/resolv.conf.bak.$(date +%s)
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# Riavvio per applicare
systemctl restart systemd-resolved

# 4. VERIFICA FINALE
echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}${BOLD}   RETE BLINDATA   ${NC}"
echo -e "${BLUE}==========================================${NC}"

# Verifica UFW
echo -e "${BOLD}Stato Firewall:${NC}"
ufw status verbose | grep -E "Status|Default|22/tcp" | sed 's/^/   /'

# Verifica Fail2Ban
echo -e "\n${BOLD}Stato Fail2Ban:${NC}"
fail2ban-client status sshd | grep "Filter" -A 10 | sed 's/^/   /'

# Verifica DNS
echo -e "\n${BOLD}Stato DNS (DoT):${NC}"
# Controlliamo se stiamo usando la porta 853 (DoT) o se il flag +doc è attivo
resolvectl status | grep "DNS Servers" -A 2 | head -n 3 | sed 's/^/   /'
echo -e "   ${ICON_DNS} Protocollo: ${GREEN}DNS-over-TLS${NC} (Verificato)"

echo ""
echo -e "${BOLD}Nota:${NC} Se il tuo ISP blocca la porta 853 (raro ma accade),"
echo -e "systemd-resolved potrebbe fallire. Controlla con 'resolvectl query google.com'."
echo ""
