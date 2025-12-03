from typing import override

from archinstall.default_profiles.profile import GreeterType, ProfileType
from archinstall.default_profiles.xorg import XorgProfile


class PlasmaProfile(XorgProfile):
	def __init__(self) -> None:
		super().__init__('KDE Plasma', ProfileType.DesktopEnv)

	@property
	@override
	def packages(self) -> list[str]:
		return [
			'ark',
			"plasma-desktop",   # Shell e KWin
    		"wayland",          # Protocollo base
    		"egl-wayland",      # Essenziale per NVIDIA (male non fa sugli altri)
    		"xdg-desktop-portal-kde", # Fondamentale per Screen Sharing / Flatpak in Wayland
		    "powerdevil",       # Gestione energia (sospensione, luminosità)
		    "kscreen",          # Gestione multi-monitor e risoluzione
		    "plasma-nm",        # Applet NetworkManager (Wi-Fi UI)
		    "plasma-pa",        # Applet PulseAudio/Pipewire (Volume UI)
		    "bluedevil",        # Gestione Bluetooth (Rimuovi se non usi BT)
		    "breeze",           # Tema base (per coerenza visiva SDDM)
		    "breeze-gtk",       # Coerenza per app GTK/Gnome
		    "dolphin",          # File Manager
		    "alacritty",        # Terminale (GPU Accelerated)
		    "ffmpegthumbs",     # Thumbnail video per Dolphin
		]

	@property
	@override
	def default_greeter_type(self) -> GreeterType:
		return GreeterType.Sddm
