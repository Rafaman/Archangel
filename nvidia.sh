#!/bin/bash

# ==============================================================================
#  NVIDIA EARLY KMS ENABLER (mkinitcpio)
# ==============================================================================
#  1. Aggiunge i moduli NVIDIA a /etc/mkinitcpio.conf
#  2. Rimuove il parametro ridondante da GRUB
#  3. Rigenera le Unified Kernel Images (UKI)
#  4. Firma automaticamente le nuove immagini per Secure Boot
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ICON_GPU="[🎮]"
ICON_CONF="[📝]"
ICON_BUILD="[🔨]"
ICON_KEY="[🔑]"
ICON_WARN="[!]"

MKINITCPIO_CONF="/etc/mkinitcpio.conf"
GRUB_CONF="/etc/default/grub"

# --- FUNZIONI ---

log_info() { echo -e "${BLUE}${ICON_CONF} $1${NC}"; }
log_success() { echo -e "${GREEN}[OK] $1${NC}"; }
check_root() { if [[ $EUID -ne 0 ]]; then echo "${RED}Serve root.${NC}"; exit 1; fi; }

# --- MAIN ---

clear
echo -e "${BLUE}${BOLD}   NVIDIA EARLY LOADING SETUP   ${NC}"
check_root

# 1. MODIFICA MKINITCPIO.CONF
# Cerchiamo di essere chirurgici. Aggiungiamo i moduli se mancano.
MODULES_STRING="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

log_info "Controllo $MKINITCPIO_CONF..."

if grep -q "nvidia_drm" "$MKINITCPIO_CONF"; then
    echo -e "${YELLOW}Sembra che i moduli NVIDIA siano già presenti in MODULES. Salto modifica.${NC}"
else
    # Backup
    cp "$MKINITCPIO_CONF" "$MKINITCPIO_CONF.bak.$(date +%s)"
    
    # Aggiunta moduli. Usiamo sed per inserire i moduli dentro le parentesi di MODULES=(...)
    # Nota: Questo assume una config standard. Se è molto custom, controlla manualmente.
    sed -i "s/MODULES=(/MODULES=($MODULES_STRING /" "$MKINITCPIO_CONF"
    
    # Rimuoviamo 'kms' dall'HOOKS se presente (conflitto con nvidia proprietari in early boot)
    # Arch Wiki consiglia di rimuovere 'kms' dai HOOKS quando si usa nvidia modules
    sed -i "s/ kms / /" "$MKINITCPIO_CONF"
    
    log_success "Moduli aggiunti: $MODULES_STRING"
fi

# 2. PULIZIA GRUB (Opzionale ma pulito)
# Se usiamo Early KMS, nvidia_drm.modeset=1 nella cmdline è ridondante 
# (il modulo nvidia_drm lo prende dalle opzioni o lo setta di default su Arch moderno),
# MA per sicurezza estrema su Wayland, è meglio lasciarlo O spostarlo in /etc/modprobe.d/
# Per ora, lasciamolo in GRUB come "cintura e bretelle", non fa male.

# Ma creiamo il file di configurazione modprobe per sicurezza
echo "options nvidia_drm modeset=1" > /etc/modprobe.d/nvidia.conf
echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" >> /etc/modprobe.d/nvidia.conf
log_success "Configurazione /etc/modprobe.d/nvidia.conf creata."


# 3. RIGENERAZIONE UKI
echo -e "\n${BLUE}${ICON_BUILD} Rigenerazione Immagini Kernel (UKI)...${NC}"
mkinitcpio -P

if [ $? -ne 0 ]; then
    echo -e "${RED}Errore durante mkinitcpio. Interrompo.${NC}"
    exit 1
fi

# 4. FIRMA SECURE BOOT
echo -e "\n${BLUE}${ICON_KEY} Firma Digitale UKI per Secure Boot...${NC}"

# Verifichiamo se abbiamo lo script di firma generato nei passi precedenti
if [ -x "/usr/local/bin/sign-assets.sh" ]; then
    /usr/local/bin/sign-assets.sh
    log_success "Immagini firmate e pronte."
else
    echo -e "${YELLOW}${ICON_WARN} Script di firma non trovato. Ricordati di firmare manualmente le UKI!${NC}"
    echo -e "Comando suggerito: sbsign --key MOK.key --cert MOK.crt ..."
fi

echo ""
echo -e "${GREEN}${BOLD}EARLY KMS ABILITATO.${NC}"
echo "Al prossimo riavvio, i driver NVIDIA verranno caricati istantaneamente."
