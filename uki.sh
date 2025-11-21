#!/bin/bash

# ==============================================================================
#  UKI PATH FIXER
# ==============================================================================
#  Modifica il preset di mkinitcpio per puntare esattamente a:
#  /boot/EFI/EFI/Linux/arch-linux-zen.efi
# ==============================================================================

# --- CONFIGURAZIONE ---
PRESET_FILE="/etc/mkinitcpio.d/linux-zen.preset"
TARGET_DIR="/boot/EFI/EFI/Linux"
TARGET_UKI="$TARGET_DIR/arch-linux-zen.efi"

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}:: Configurazione Percorso UKI...${NC}"

# 1. Verifica esistenza preset
if [[ ! -f "$PRESET_FILE" ]]; then
    echo -e "${RED}Errore: Il file $PRESET_FILE non esiste.${NC}"
    echo "Assicurati di aver installato il pacchetto 'linux-zen'."
    exit 1
fi

# 2. Backup del file preset
echo "   Backup di sicurezza del preset..."
cp "$PRESET_FILE" "$PRESET_FILE.bak.pathfix"

# 3. Creazione della directory target (se non esiste)
# Questo risolve l'errore "must be writable"
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "   Creazione directory: ${BOLD}$TARGET_DIR${NC}"
    mkdir -p "$TARGET_DIR"
else
    echo -e "   Directory target esistente: ${GREEN}[OK]${NC}"
fi

# 4. Modifica del file Preset con sed
echo "   Aggiornamento percorso in $PRESET_FILE..."

# Passo A: Se la riga è commentata (#default_uki=), la scommentiamo
sed -i 's/^#default_uki=/default_uki=/' "$PRESET_FILE"

# Passo B: Sostituiamo qualsiasi cosa ci sia in default_uki="..." con il tuo percorso
# Usiamo il delimitatore | invece di / per non fare confusione con i path
sed -i "s|default_uki=.*|default_uki=\"$TARGET_UKI\"|" "$PRESET_FILE"

# 5. Verifica della modifica
if grep -q "$TARGET_UKI" "$PRESET_FILE"; then
    echo -e "${GREEN}   [OK] Percorso aggiornato correttamente nel file.${NC}"
else
    echo -e "${RED}   [ERR] Modifica fallita. Controlla il file manualmente.${NC}"
    exit 1
fi

# 6. Rigenerazione dell'immagine
echo -e "\n${BLUE}${BOLD}:: Rigenerazione UKI (mkinitcpio -P)...${NC}"
mkinitcpio -P

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}${BOLD}SUCCESSO!${NC}"
    echo -e "L'immagine è stata creata in: ${BOLD}$TARGET_UKI${NC}"
    
    # 7. Firma (Opzionale, se hai lo script precedente)
    if [ -x "/usr/local/bin/sign-assets.sh" ]; then
        echo -e "   Avvio firma automatica per Secure Boot..."
        /usr/local/bin/sign-assets.sh
    fi
else
    echo -e "\n${RED}Errore durante la generazione dell'immagine.${NC}"
    exit 1
fi
