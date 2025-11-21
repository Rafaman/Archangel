#!/bin/bash

# ==============================================================================
#  LINUX ZEN HARDENING: SYSCTL OPTIMIZER
# ==============================================================================
#  Applica restrizioni di sicurezza mirate (Kernel Hardening) senza
#  sacrificare le prestazioni multimediali del kernel Zen.
#  Target: /etc/sysctl.d/99-zen-hardening.conf
# ==============================================================================

# --- STILE E COLORI ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_SHIELD="[🛡️]"
ICON_KERNEL="[🧠]"
ICON_LOCK="[🔒]"
ICON_CHECK="[✔]"
ICON_WARN="[!]"

CONF_FILE="/etc/sysctl.d/99-zen-hardening.conf"

# --- FUNZIONI ---

log_header() { echo -e "\n${PURPLE}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_CHECK} $1${NC}"; }
log_info() { echo -e "${BLUE}${ICON_KERNEL} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

# --- MAIN ---

clear
echo -e "${CYAN}${BOLD}"
echo "   _  __ ___  ___  _  _  ___  _     "
echo "  | |/ /| __|| _ \| \| || __|| |    "
echo "  | ' < | _| |   /| .\` || _| | |__  "
echo "  |_|\_\|___||_|_\|_|\_||___||____| "
echo "     ZEN HARDENING & SYSCTL AUDIT   "
echo -e "${NC}"
echo -e "${BLUE}====================================${NC}"

check_root

# 1. ANALISI KERNEL CORRENTE
log_header "1. Analisi Ambiente"
CURRENT_KERNEL=$(uname -r)
echo -e "   Kernel in uso: ${BOLD}$CURRENT_KERNEL${NC}"

if [[ "$CURRENT_KERNEL" == *"zen"* ]]; then
    log_success "Kernel Zen rilevato. Ottimizzazione ideale."
else
    echo -e "${YELLOW}${ICON_WARN} Non stai usando il kernel Zen. Le regole verranno applicate comunque.${NC}"
fi

# 2. SCRITTURA CONFIGURAZIONE
log_header "2. Applicazione Regole Sysctl (Hardening Chirurgico)"

if [[ -f "$CONF_FILE" ]]; then
    cp "$CONF_FILE" "$CONF_FILE.bak.$(date +%s)"
    log_info "Backup configurazione esistente creato."
fi

echo -e "   Scrittura in ${BOLD}$CONF_FILE${NC}..."

cat <<EOF > "$CONF_FILE"
# =================================================================
# HARDENING CHIRURGICO PER LINUX-ZEN
# Generato automaticamente da script di automazione
# =================================================================

# 1. Protezione Memoria Kernel (ASLR/ROP Mitigation)
# Nasconde indirizzi memoria kernel (/proc/kallsyms) a utenti non privilegiati.
kernel.kptr_restrict = 2

# 2. Protezione Log Kernel (Info Leakage)
# Restringe l'accesso a dmesg (buffer messaggi) solo a root.
# Previene la ricognizione hardware/memoria da parte di attaccanti.
kernel.dmesg_restrict = 1

# 3. Hardening eBPF (Privilege Escalation)
# Disabilita l'uso di eBPF per utenti normali.
# eBPF è potente ma vettore frequente di attacchi JIT spraying.
kernel.unprivileged_bpf_disabled = 1

# 4. Restrizione Ptrace (Code Injection)
# Impedisce a un processo di debuggarne/tracciarne un altro a meno che
# non sia un discendente diretto. Blocca memory scraping di password.
kernel.yama.ptrace_scope = 2

# 5. Hardening JIT Compiler (Obfuscation)
# Offusca gli offset delle istruzioni BPF compilate JIT per
# rendere difficile lo sfruttamento di bug nel compilatore stesso.
net.core.bpf_jit_harden = 2

# =================================================================
EOF

log_success "File di configurazione creato."

# 3. CARICAMENTO REGOLE
log_header "3. Caricamento a Runtime"
echo -e "   Applicazione modifiche al kernel attivo..."

# sysctl --system ricarica tutti i file, -p carica solo quello specificato
if sysctl -p "$CONF_FILE" &> /dev/null; then
    log_success "Parametri caricati nel kernel con successo."
else
    echo -e "${RED}${ICON_WARN} Errore nel caricamento dei parametri. Verifica la sintassi.${NC}"
    exit 1
fi

# 4. AUDIT DI VERIFICA
log_header "4. Audit di Sicurezza (Verifica Valori Attivi)"

# Funzione interna per verificare un valore
verify_param() {
    key=$1
    expected=$2
    # Legge il valore attuale dal kernel
    current=$(sysctl -n "$key" 2>/dev/null)
    
    if [[ "$current" == "$expected" ]]; then
        echo -e "${GREEN}${ICON_SHIELD} OK: $key = $current${NC}"
    else
        echo -e "${RED}${ICON_WARN} FAIL: $key = $current (Atteso: $expected)${NC}"
    fi
}

verify_param "kernel.kptr_restrict" "2"
verify_param "kernel.dmesg_restrict" "1"
verify_param "kernel.unprivileged_bpf_disabled" "1"
verify_param "kernel.yama.ptrace_scope" "2"
verify_param "net.core.bpf_jit_harden" "2"

echo ""
echo -e "${BLUE}====================================${NC}"
echo -e "${GREEN}${BOLD}   KERNEL HARDENING COMPLETATO   ${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "Nota: D'ora in poi, per vedere i log del kernel (dmesg)"
echo -e "dovrai usare sudo: ${BOLD}sudo dmesg${NC}"
echo ""
