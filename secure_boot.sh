#!/bin/bash

# ==============================================================================
#  SECURE BOOT & UKI ARCHITECT (Shim + GRUB + UKI)
# ==============================================================================
#  1. Generazione chiavi MOK (Machine Owner Key)
#  2. Configurazione Unified Kernel Image (UKI) in mkinitcpio
#  3. Creazione Hook di firma automatica (Pacman)
#  4. Preparazione certificati per enroll
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ICON_KEY="[🔑]"
ICON_CERT="[📜]"
ICON_GEAR="[⚙]"
ICON_WARN="[!]"
ICON_OK="[✔]"

# Percorsi Chiavi
KEY_DIR="/var/lib/sb-keys"
MOK_NAME="MOK"
EFI_DIR="/boot/efi" # Adatta se il tuo mount point è diverso (es /boot)

# --- FUNZIONI ---

log_header() { echo -e "\n${BLUE}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_OK} $1${NC}"; }
log_info() { echo -e "${CYAN}${ICON_GEAR} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

check_deps() {
    local deps=("sbsign" "openssl" "mokutil" "grub" "mkinitcpio")
    for cmd in "${deps[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Manca il comando: $cmd${NC}"
            echo -e "Installa: sbsigntools, openssl, mokutil, grub"
            exit 1
        fi
    done
}

# --- MAIN ---

clear
echo -e "${CYAN}${BOLD}   SECURE BOOT & UKI SETUP   ${NC}"
echo -e "${BLUE}=============================${NC}"

check_root
check_deps

# 1. Generazione Chiavi MOK
log_header "1. Generazione Machine Owner Key (MOK)"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [[ -f "$KEY_DIR/$MOK_NAME.key" ]]; then
    echo -e "${YELLOW}Chiavi già presenti in $KEY_DIR. Salto generazione.${NC}"
else
    log_info "Generazione coppia chiavi..."
    openssl req -new -x509 -newkey rsa:2048 -keyout "$KEY_DIR/$MOK_NAME.key" \
        -out "$KEY_DIR/$MOK_NAME.crt" -nodes -days 3650 -subj "/CN=Arch Linux Custom MOK/"
    
    # Conversione in DER per mokutil
    openssl x509 -in "$KEY_DIR/$MOK_NAME.crt" -out "$KEY_DIR/$MOK_NAME.cer" -outform DER
    
    chmod 600 "$KEY_DIR/$MOK_NAME.key"
    log_success "Chiavi generate in $KEY_DIR"
fi

# 2. Preparazione Cmdline Kernel
log_header "2. Configurazione Kernel Command Line"
# Per le UKI, la cmdline deve essere incorporata nel file.
# Estraiamo la cmdline attuale o usiamo /etc/kernel/cmdline

CMDLINE_FILE="/etc/kernel/cmdline"
mkdir -p "$(dirname "$CMDLINE_FILE")"

if [[ ! -f "$CMDLINE_FILE" ]]; then
    # Tentativo di estrarre UUID root
    ROOT_UUID=$(findmnt / -n -o UUID)
    echo -e "   Rilevato UUID Root: $ROOT_UUID"
    
    # Parametri base + ottimizzazioni SSD precedenti + crittografia
    # NOTA: Assicurati che 'cryptdevice=UUID=...:cryptroot' sia corretto per il tuo setup LUKS
    echo "root=UUID=$ROOT_UUID rw quiet loglevel=3 cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot" > "$CMDLINE_FILE"
    
    echo -e "${YELLOW}${ICON_WARN} Ho creato una cmdline di base in $CMDLINE_FILE.${NC}"
    echo -e "${YELLOW}IMPORTANTE: Controllala prima di riavviare! Deve contenere i parametri LUKS corretti.${NC}"
else
    log_success "File cmdline esistente: $CMDLINE_FILE"
fi

# 3. Configurazione mkinitcpio per UKI
log_header "3. Configurazione Preset UKI (mkinitcpio)"

PRESET_FILE="/etc/mkinitcpio.d/linux-zen.preset"

if [[ -f "$PRESET_FILE" ]]; then
    # Backup
    cp "$PRESET_FILE" "$PRESET_FILE.bak"
    
    # Modifica per abilitare UKI
    # Commentiamo le righe 'default_image' e scommentiamo/configuriamo 'default_uki'
    sed -i 's|^default_image|#default_image|g' "$PRESET_FILE"
    sed -i 's|^#default_uki|default_uki|g' "$PRESET_FILE"
    
    # Assicuriamoci che punti alla directory EFI corretta per GRUB o Systemd-boot
    # Per GRUB chainloading, mettiamolo in /boot/efi/EFI/Linux/
    mkdir -p "$EFI_DIR/EFI/Linux"
    
    if ! grep -q "default_uki=" "$PRESET_FILE"; then
        echo "default_uki=\"$EFI_DIR/EFI/Linux/arch-zen.efi\"" >> "$PRESET_FILE"
    fi
    
    log_success "Preset linux-zen configurato per output UKI."
else
    echo -e "${RED}Errore: Preset linux-zen non trovato. Hai installato linux-zen?${NC}"
    exit 1
fi

# 4. Creazione Hook di Firma Automatica
log_header "4. Installazione Hook di Firma (Pacman)"

HOOK_DIR="/etc/pacman.d/hooks"
mkdir -p "$HOOK_DIR"
SIGN_HOOK="$HOOK_DIR/sign-uki.hook"

cat <<EOF > "$SIGN_HOOK"
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-zen
Target = systemd
Target = grub
Target = shim-signed

[Action]
Description = Firma UKI e Bootloader per Secure Boot...
When = PostTransaction
Exec = /usr/local/bin/sign-assets.sh
EOF

# Creazione script helper per la firma
SIGN_SCRIPT="/usr/local/bin/sign-assets.sh"
cat <<EOF > "$SIGN_SCRIPT"
#!/bin/bash
# Script di firma automatica generato
KEY="$KEY_DIR/$MOK_NAME.key"
CERT="$KEY_DIR/$MOK_NAME.crt"

echo ":: Firma in corso con sbsign..."

# 1. Firma UKI (se esiste)
UKI_PATH="$EFI_DIR/EFI/Linux/arch-zen.efi"
if [[ -f "\$UKI_PATH" ]]; then
    sbsign --key "\$KEY" --cert "\$CERT" --output "\$UKI_PATH" "\$UKI_PATH"
    echo "   -> UKI firmata."
fi

# 2. Firma GRUB (core image)
GRUB_PATH="$EFI_DIR/EFI/grub/grubx64.efi" # Verifica il tuo percorso!
if [[ -f "\$GRUB_PATH" ]]; then
    sbsign --key "\$KEY" --cert "\$CERT" --output "\$GRUB_PATH" "\$GRUB_PATH"
    echo "   -> GRUB firmato."
fi
EOF

chmod +x "$SIGN_SCRIPT"
log_success "Hook e script di firma installati."

# 5. Rigenerazione Immagini
log_header "5. Generazione e Firma iniziale UKI"
mkinitcpio -P
# Eseguiamo lo script di firma manualmente per la prima volta
/usr/local/bin/sign-assets.sh

# 6. Istruzioni MOK Enrollment
log_header "Setup Completato. Istruzioni Finali:"
echo -e "${YELLOW}Devi ora importare la chiave nel BIOS/Shim:${NC}"
echo -e "1. Esegui ora: ${BOLD}mokutil --import $KEY_DIR/$MOK_NAME.cer${NC}"
echo -e "2. Ti verrà chiesta una password usa e getta."
echo -e "3. Riavvia il sistema."
echo -e "4. Al boot vedrai la schermata blu 'Shim UEFI key management'."
echo -e "5. Seleziona 'Enroll MOK', 'View key 0', verifica che sia la tua 'Arch Linux Custom MOK'."
echo -e "6. Conferma e inserisci la password scelta al punto 2."

echo ""
echo -e "${BOLD}Vuoi eseguire mokutil --import ora?${NC}"
echo -e -n "(s/N): "
read -r resp
if [[ "$resp" =~ ^([sS][iI]|[sS])$ ]]; then
    mokutil --import "$KEY_DIR/$MOK_NAME.cer"
else
    echo "Ricordati di farlo prima di attivare Secure Boot!"
fi
