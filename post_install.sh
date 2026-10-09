#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN: ARCH LINUX (INTEL + AUDIO + AUR + ESCRITORIO)
# ==============================================================================
# Ejecutar este script DESPUÉS de reiniciar e iniciar sesión con tu usuario.
# ==============================================================================

set -euo pipefail

VERDE="\e[32m"
AZUL="\e[34m"
ROJO="\e[31m"
RESET="\e[0m"

# Validar que no se ejecute como root
if [ "$EUID" -eq 0 ]; then
    echo -e "${ROJO}[ERROR] No ejecutes este script como 'root' ni con 'sudo'.${RESET}"
    echo -e "Ejecútalo con tu usuario normal (el script solicitará sudo cuando lo requiera):"
    echo -e "  su - <tu_usuario>"
    echo -e "  ./post_install.sh"
    exit 1
fi

echo -e "${AZUL}====================================================${RESET}"
echo -e "${AZUL}      POST-INSTALACIÓN DE ARCH LINUX               ${RESET}"
echo -e "${AZUL}====================================================${RESET}\n"

# 1. Servidor de audio PulseAudio y utilidades
echo -e "${VERDE}[+] Instalando servidor de audio (PulseAudio) y utilidades básicas...${RESET}"
# Si pipewire-pulse estuviese instalado, se remueve para evitar conflictos con pulseaudio
sudo pacman -S --needed --noconfirm \
    pulseaudio pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol \
    bluez bluez-utils \
    fastfetch btop ripgrep fd eza bat \
    ttf-font-awesome ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji otf-font-awesome \
    ffmpeg p7zip unrar unzip code firefox openssh

# Habilitar Bluetooth
sudo systemctl enable --now bluetooth || true
sudo systemctl enable --now systemd-timesyncd

# 2. Instalar AUR Helper (yay)
if ! command -v yay &> /dev/null; then
    echo -e "\n${VERDE}[+] Instalando el AUR helper (yay)...${RESET}"
    cd /tmp
    rm -rf yay
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

# 3. Menú interactivo de selección de entorno de escritorio
echo -e "\n${AZUL}Selecciona el entorno gráfico que deseas instalar:${RESET}"
echo "1) KDE Plasma (Recomendado, completo y configurable)"
echo "2) GNOME (Moderno y minimalista)"
echo "3) Hyprland (Tiling Wayland fluido y ligero)"
echo "4) Omitir por ahora (Solo terminal)"
read -rp "Opción [1-4]: " DE_CHOICE

case "$DE_CHOICE" in
    1)
        echo -e "${VERDE}[+] Instalando KDE Plasma y SDDM...${RESET}"
        sudo pacman -S --needed --noconfirm plasma kde-applications sddm
        sudo systemctl enable sddm
        ;;
    2)
        echo -e "${VERDE}[+] Instalando GNOME y GDM...${RESET}"
        sudo pacman -S --needed --noconfirm gnome gnome-extra gdm
        sudo systemctl enable gdm
        ;;
    3)
        echo -e "${VERDE}[+] Instalando Hyprland, Waybar y Kitty...${RESET}"
        sudo pacman -S --needed --noconfirm hyprland waybar hyprlauncher hyprpaper kitty dolphin polkit-kde-agent dunst grim slurp sddm \
            fish gnome-calendar gimp python-openai-whisper wiremix ffmpeg telegram-desktop freecad blender qalculate-gtk vlc 
        sudo systemctl enable sddm
        ;;
    *)
        echo -e "Omitiendo instalación de entorno gráfico."
        ;;
esac

echo -e "\n${VERDE}====================================================${RESET}"
echo -e "${VERDE}  ¡POST-INSTALACIÓN COMPLETADA EXITOSAMENTE!        ${RESET}"
echo -e "${VERDE}====================================================${RESET}"
echo -e "Puedes reiniciar el equipo para iniciar en tu nuevo entorno: ${AZUL}systemctl reboot${RESET}\n"
