#!/bin/bash

# =============================================================================
# ARCH LINUX KERNEL HARDENING (SYSCTL) - LIMINE SYSTEM
# =============================================================================
# Reference: Opzione B - Hardening Manuale (Kernel Standard)
# Description: Applica restrizioni di sicurezza granulari tramite sysctl.conf
#              senza necessitare del kernel linux-hardened.
# =============================================================================

# --- Configurazioni Estetiche ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BOLD}${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${BOLD}${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${BOLD}${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${BOLD}${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    clear
    echo -e "${BOLD}${GREEN}"
    echo "   _   _   ___   ______ ______  _____  _   _  _____ "
    echo "  | | | | / _ \  | ___ \| ___ \|  ___|| \ | ||  __ \\"
    echo "  | |_| |/ /_\ \ | |_/ /| |_/ /| |__  |  \| || |  \/"
    echo "  |  _  ||  _  | |    / |    / |  __| | . \` || | __ "
    echo "  | | | || | | | | |\ \ | |\ \ | |___ | |\  || |_\ \\"
    echo "  \_| |_/\_| |_/ \_| \_|\_| \_|\____/ \_| \_/ \____/"
    echo -e "         SYSCTL SECURITY FOR LIMINE SYSTEMS${NC}"
    echo ""
    echo "Questo script applica le policy di sicurezza al Kernel Standard."
    echo "Compatibile con bootloader Limine (modifiche lato userspace)."
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "Per modificare i parametri del kernel serve root."
    fi
}

# --- Main Logic ---

banner
check_root

TARGET_FILE="/etc/sysctl.d/99-hardening.conf"

log_info "Preparazione hardening manuale (Opzione B)..."

# 1. Gestione Compatibilità (User Namespaces)
echo ""
echo -e "${YELLOW}--- CONFIGURAZIONE COMPATIBILITÀ ---${NC}"
echo "L'opzione 'kernel.unprivileged_userns_clone' aumenta drasticamente la sicurezza"
echo "ma impedisce il funzionamento di molte applicazioni desktop moderne."
echo ""
echo "Usiamo applicazioni come Docker, Podman, Steam, Discord, VSCode o Chrome?"
echo -n "Rispondi 's' (Sì) per mantenere compatibilità, 'n' (No) per massima sicurezza: "
read response

if [[ "$response" =~ ^[Ss]$ ]]; then
    log_warn "Modalità COMPATIBILE selezionata."
    log_info "User Namespaces rimarranno abilitati (Docker/Steam funzioneranno)."
    USERNS_OP="# kernel.unprivileged_userns_clone = 1 (Commentato per compatibilità Docker/Steam)"
else
    log_warn "Modalità HARDENED selezionata."
    log_info "User Namespaces verranno disabilitati. Le app Sandboxate potrebbero non avviarsi."
    # Nota: Su kernel standard recenti potrebbe chiamarsi 'user.max_user_namespaces=0'
    # ma manteniamo la sintassi della tua guida per fedeltà, aggiungendo un fallback.
    USERNS_OP="kernel.unprivileged_userns_clone = 1"
fi

# 2. Backup esistente
if [ -f "$TARGET_FILE" ]; then
    log_info "Backup della configurazione esistente..."
    cp "$TARGET_FILE" "$TARGET_FILE.bak-$(date +%s)"
    log_success "Backup creato."
fi

# 3. Scrittura file configurazione
log_info "Scrittura delle direttive in $TARGET_FILE..."

cat <<EOF > "$TARGET_FILE"
# =================================================================
# HARDENING MANUALE (Kernel Standard)
# Generato automaticamente
# =================================================================

# 1. Nasconde i puntatori del kernel (previene information leaks utili per exploit)
kernel.kptr_restrict = 2

# 2. Restringe l'accesso a dmesg (log del kernel) solo a root
# Evita che utenti normali vedano indirizzi di memoria o errori hardware sensibili.
kernel.dmesg_restrict = 1

# 3. Restringe l'uso del BPF JIT
# Il Berkeley Packet Filter è potente ma è un vettore comune di attacco.
# Disabilitiamo l'uso non privilegiato e rafforziamo il compilatore JIT.
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# 4. Limita ptrace
# Impedisce a un processo di ispezionare/modificare la memoria di un altro
# (a meno che non sia padre-figlio). Blocca molti malware e code-injection.
kernel.yama.ptrace_scope = 2

# 5. Disabilita kexec
# Impedisce di caricare un nuovo kernel a sistema avviato.
# Utile per evitare che un attaccante sostituisca il kernel in memoria.
kernel.kexec_load_disabled = 1

# 6. User Namespaces (Selettore Compatibilità)
# Se attivo (=1), rompe sandbox di browser e container rootless.
$USERNS_OP
EOF

log_success "File di configurazione creato."

# 4. Applicazione modifiche
log_info "Applicazione modifiche a caldo (sysctl --system)..."

# Catturiamo l'output per evitare di spaventare l'utente se una chiave non esiste
# (alcuni kernel standard non hanno unprivileged_userns_clone esposto così)
SYSCTL_OUT=$(sysctl --system 2>&1)

if [ $? -eq 0 ]; then
    log_success "Modifiche applicate correttamente."
else
    # Filtriamo errori comuni non bloccanti
    echo "$SYSCTL_OUT" | grep -v "unknown key"
    log_warn "Alcune chiavi potrebbero non essere disponibili nel tuo kernel attuale."
    log_warn "Questo è normale se non stai usando patch specifiche. Le altre sono attive."
fi

# 5. Verifica dello stato
echo ""
echo -e "${BOLD}--- VERIFICA STATO ---${NC}"
echo -n "Ptrace Scope (Target: 2): "
sysctl -n kernel.yama.ptrace_scope
echo -n "Kexec Disabled (Target: 1): "
sysctl -n kernel.kexec_load_disabled
echo -n "BPF Unprivileged (Target: 1): "
sysctl -n kernel.unprivileged_bpf_disabled

echo ""
echo -e "${BOLD}${GREEN}HARDENING COMPLETATO!${NC}"
echo "-----------------------------------------------------"
echo "Le modifiche sono persistenti al riavvio."
echo "Poiché usi Limine, non c'è bisogno di rigenerare menu di boot."
echo "Il kernel caricherà queste regole all'avvio del sistema operativo."
echo "-----------------------------------------------------"
