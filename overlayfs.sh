#!/bin/bash

# ==============================================================================
#  SNAPSHOT BOOT FIXER (OVERLAYFS)
# ==============================================================================
#  Risolve l'errore di boot Read-Only installando un hook initramfs
#  che crea un layer scrivibile in RAM sopra lo snapshot.
# ==============================================================================

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

REAL_USER=${SUDO_USER:-$USER}
MKINITCPIO_CONF="/etc/mkinitcpio.conf"

echo -e "${BLUE}${BOLD}:: Configurazione Boot Snapshot (OverlayFS)...${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Serve root.${NC}"
   exit 1
fi

# 1. Installazione hook da AUR
# Serve paru (configurato nello step manutenzione)
if ! pacman -Qi grub-btrfs-overlayfs &> /dev/null; then
    echo -e "   Installazione pacchetto hook..."
    # Eseguiamo come utente reale perché makepkg non gira come root
    sudo -u "$REAL_USER" paru -S --noconfirm grub-btrfs-overlayfs
else
    echo -e "${GREEN}   [OK] grub-btrfs-overlayfs già installato.${NC}"
fi

# 2. Configurazione mkinitcpio.conf
echo -e "   Configurazione HOOKS in $MKINITCPIO_CONF..."

# Backup
cp "$MKINITCPIO_CONF" "$MKINITCPIO_CONF.bak.overlay"

# Logica di inserimento: L'hook deve stare DOPO 'filesystems'
if grep -q "grub-btrfs-overlayfs" "$MKINITCPIO_CONF"; then
    echo -e "${GREEN}   [OK] Hook già presente.${NC}"
else
    # Sed magico: cerca la parola 'filesystems' e appende l'hook subito dopo
    sed -i 's/\(filesystems\)/\1 grub-btrfs-overlayfs/' "$MKINITCPIO_CONF"
    
    # Verifica
    if grep -q "grub-btrfs-overlayfs" "$MKINITCPIO_CONF"; then
        echo -e "${GREEN}   [OK] Hook inserito correttamente.${NC}"
    else
        echo -e "${RED}   [ERR] Inserimento automatico fallito.${NC}"
        echo -e "   Aggiungi manualmente 'grub-btrfs-overlayfs' alla riga HOOKS dopo 'filesystems'."
        exit 1
    fi
fi

# 3. Rigenerazione Immagini (UKI)
echo -e "   Rigenerazione initramfs/UKI..."
mkinitcpio -P

if [ $? -ne 0 ]; then
    echo -e "${RED}Errore mkinitcpio.${NC}"
    exit 1
fi

# 4. Firma Secure Boot (Se presente script di firma)
if [ -x "/usr/local/bin/sign-assets.sh" ]; then
    echo -e "   Firma automatica Secure Boot..."
    /usr/local/bin/sign-assets.sh
fi

# 5. Rigenerazione GRUB
echo -e "   Aggiornamento menu GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null

echo ""
echo -e "${GREEN}${BOLD}FIX APPLICATO.${NC}"
echo -e "Ora, quando selezioni uno snapshot da GRUB:"
echo -e "1. Verrà montato in Read-Only."
echo -e "2. Verrà creato un OverlayFS temporaneo in RAM."
echo -e "3. Il sistema si avvierà normalmente permettendoti di fare login."
echo -e "4. Una volta dentro, potrai dare 'snapper rollback' per ripristinare."
