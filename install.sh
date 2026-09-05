#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE INSTALACIÓN AUTOMATIZADA: ARCH LINUX (UEFI + INTEL)
# Proyecto: BTW_Arch
# ==============================================================================
# Este script realiza:
# 1. Configuración de teclado y hora (NTP).
# 2. Particionado automático GPT (EFI: 1GB, SWAP: 4GB, ROOT: Resto).
# 3. Formateo y montaje de unidades.
# 4. Instalación de paquetes base con 'pacstrap' (con soporte Intel).
# 5. Configuración del sistema en chroot (Usuarios, Locale, GRUB, Drivers Intel).
# ==============================================================================

set -euo pipefail

# Colores para mensajes
VERDE="\e[32m"
AZUL="\e[34m"
AMARILLO="\e[33m"
ROJO="\e[31m"
RESET="\e[0m"

echo -e "${AZUL}====================================================${RESET}"
echo -e "${AZUL}     INSTALADOR DE ARCH LINUX - PERFIL INTEL       ${RESET}"
echo -e "${AZUL}====================================================${RESET}\n"

# 1. Verificar si estamos en modo UEFI
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo -e "${ROJO}[ERROR] El sistema no arrancó en modo UEFI. Abortando.${RESET}"
    exit 1
fi

# 2. Configurar teclado en español latinoamericano
echo -e "${VERDE}[+] Configurando teclado latinoamericano...${RESET}"
loadkeys la-latin1

# 3. Sincronizar reloj
echo -e "${VERDE}[+] Sincronizando hora del sistema (NTP)...${RESET}"
timedatectl set-ntp true

# 4. Seleccionar el disco
echo -e "\n${AZUL}[*] Discos disponibles en el equipo:${RESET}"
lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop\|airootfs"
echo ""

read -rp "Ingresa el nombre del disco a instalar (ejemplo: sda o nvme0n1): " DISK_NAME
TARGET_DISK="/dev/${DISK_NAME}"

if [ ! -b "$TARGET_DISK" ]; then
    echo -e "${ROJO}[ERROR] El dispositivo $TARGET_DISK no existe.${RESET}"
    exit 1
fi

# 5. Solicitar datos de usuario y sistema
read -rp "Nombre del equipo (Hostname) [archlinux]: " HOST_NAME
HOST_NAME=${HOST_NAME:-archlinux}

read -rp "Nombre de tu usuario normal: " USER_NAME
if [ -z "$USER_NAME" ]; then
    echo -e "${ROJO}[ERROR] El nombre de usuario no puede estar vacío.${RESET}"
    exit 1
fi

read -rsp "Contraseña para superusuario (root): " ROOT_PASSWORD
echo ""
read -rsp "Contraseña para el usuario '$USER_NAME': " USER_PASSWORD
echo ""

echo -e "\n${ROJO}====================================================${RESET}"
echo -e "${ROJO}  ¡ADVERTENCIA: TODOS LOS DATOS EN $TARGET_DISK SERÁN BORRADOS!${RESET}"
echo -e "${ROJO}====================================================${RESET}"
read -rp "¿Estás seguro de continuar? (escribe 'si' para proceder): " CONFIRM

if [ "$CONFIRM" != "si" ]; then
    echo -e "${AMARILLO}[!] Instalación cancelada por el usuario.${RESET}"
    exit 0
fi

# 6. Definir nomenclatura de particiones (SATA vs NVMe)
if [[ "$TARGET_DISK" =~ nvme ]]; then
    PART_EFI="${TARGET_DISK}p1"
    PART_SWAP="${TARGET_DISK}p2"
    PART_ROOT="${TARGET_DISK}p3"
else
    PART_EFI="${TARGET_DISK}1"
    PART_SWAP="${TARGET_DISK}2"
    PART_ROOT="${TARGET_DISK}3"
fi

# 7. Desmontar particiones previas si existiesen
echo -e "\n${VERDE}[+] Limpiando montajes previos...${RESET}"
swapoff -a || true
umount -R /mnt 2>/dev/null || true

# 8. Particionado automático con sgdisk (GPT)
echo -e "${VERDE}[+] Particionando el disco $TARGET_DISK...${RESET}"
# Borrar tablas de particiones previas
sgdisk --zap-all "$TARGET_DISK"

# Crear particiones:
# 1. EFI: 1GiB (Tipo EF00)
# 2. Swap: 4GiB (Tipo 8200)
# 3. Root: Resto del disco (Tipo 8304 - Linux x86-64 root)
sgdisk -n 1:0:+1G  -t 1:ef00 -c 1:"EFI System Partition" "$TARGET_DISK"
sgdisk -n 2:0:+4G  -t 2:8200 -c 2:"Linux Swap" "$TARGET_DISK"
sgdisk -n 3:0:0    -t 3:8304 -c 3:"Arch Linux Root" "$TARGET_DISK"

# Informar al kernel de la nueva tabla
partprobe "$TARGET_DISK"
sleep 2

# 9. Formatear particiones
echo -e "${VERDE}[+] Formateando particiones...${RESET}"
mkfs.fat -F 32 -n "EFI" "$PART_EFI"
mkswap -L "SWAP" "$PART_SWAP"
mkfs.ext4 -F -L "ARCH_ROOT" "$PART_ROOT"

# 10. Montar el sistema de archivos
echo -e "${VERDE}[+] Montando particiones en /mnt...${RESET}"
mount "$PART_ROOT" /mnt
mount --mkdir "$PART_EFI" /mnt/boot
swapon "$PART_SWAP"

# 11. Refrescar llaves de pacman e instalar paquetes base
echo -e "${VERDE}[+] Instalando paquetes base y soporte Intel con pacstrap...${RESET}"
pacman -Sy archlinux-keyring --noconfirm

# Paquetes base + microcódigo Intel + drivers gráficos Intel + herramientas
pacstrap -K /mnt \
    base base-devel linux linux-firmware intel-ucode \
    mesa vulkan-intel lib32-mesa \
    networkmanager nano neovim git dosfstools e2fsprogs sudo

# 12. Generar archivo fstab
echo -e "${VERDE}[+] Generando /etc/fstab...${RESET}"
genfstab -U /mnt >> /mnt/etc/fstab

# 13. Configuración dentro de Chroot mediante script embebido
echo -e "${VERDE}[+] Configurando el nuevo sistema dentro de chroot...${RESET}"

arch-chroot /mnt /bin/bash <<EOF
set -e

# Zona horaria y reloj
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# Idioma y teclado
echo "es_CO.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=es_CO.UTF-8" > /etc/locale.conf
echo "KEYMAP=la-latin1" > /etc/vconsole.conf

# Nombre del host y hosts
echo "$HOST_NAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOST_NAME.localdomain $HOST_NAME
HOSTS

# Habilitar NetworkManager
systemctl enable NetworkManager

# Contraseña de root
echo "root:$ROOT_PASSWORD" | chpasswd

# Crear usuario y agregarlo al grupo wheel
useradd -m -G wheel -s /bin/bash "$USER_NAME"
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# Habilitar permisos de sudo para el grupo wheel
sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Instalar y configurar cargador de arranque GRUB (UEFI)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# 14. Desmontar y finalizar
echo -e "\n${VERDE}[+] Desmontando particiones...${RESET}"
swapoff -a || true
umount -R /mnt

echo -e "\n${VERDE}====================================================${RESET}"
echo -e "${VERDE}  ¡INSTALACIÓN BASE COMPLETADA CON ÉXITO!           ${RESET}"
echo -e "${VERDE}====================================================${RESET}"
echo -e "Puedes reiniciar el equipo ahora ejecutando: ${AZUL}reboot${RESET}"
echo -e "(Recuerda desconectar la memoria USB al reiniciar)\n"
