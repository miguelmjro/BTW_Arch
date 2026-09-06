#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE INSTALACIÓN AUTOMATIZADA: ARCH LINUX (UEFI + INTEL)
# Proyecto: BTW_Arch
# ==============================================================================
# Este script realiza:
# 1. Configuración de teclado y hora (NTP).
# 2. Particionado automático GPT o selección sobre particiones existentes en el disco.
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
mapfile -t DISK_LIST < <(lsblk -d -n -o NAME | grep -v -E "loop|airootfs|zram|ram" || true)

if [ "${#DISK_LIST[@]}" -eq 0 ]; then
    echo -e "${ROJO}[ERROR] No se detectaron discos de almacenamiento disponibles.${RESET}"
    exit 1
fi

for i in "${!DISK_LIST[@]}"; do
    DISK_INFO=$(lsblk -d -n -o NAME,SIZE,MODEL "/dev/${DISK_LIST[$i]}" 2>/dev/null || echo "${DISK_LIST[$i]}")
    echo -e "  $((i+1))) ${DISK_INFO}"
done
echo ""

while true; do
    read -rp "Ingresa el número o nombre del disco a instalar (ejemplo: 1 o ${DISK_LIST[0]}): " DISK_INPUT
    DISK_INPUT="${DISK_INPUT#"${DISK_INPUT%%[![:space:]]*}"}"
    DISK_INPUT="${DISK_INPUT%"${DISK_INPUT##*[![:space:]]}"}"
    DISK_INPUT="${DISK_INPUT#/dev/}"

    if [[ "$DISK_INPUT" =~ ^[0-9]+$ ]] && [ "$DISK_INPUT" -ge 1 ] && [ "$DISK_INPUT" -le "${#DISK_LIST[@]}" ]; then
        TARGET_DISK="/dev/${DISK_LIST[$((DISK_INPUT-1))]}"
        break
    elif [ -b "/dev/${DISK_INPUT}" ]; then
        TARGET_DISK="/dev/${DISK_INPUT}"
        break
    else
        echo -e "${ROJO}[ERROR] Opción o disco inválido. Por favor intenta de nuevo.${RESET}"
    fi
done

echo -e "${VERDE}[✓] Disco seleccionado: $TARGET_DISK${RESET}"

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

# 6. Modo de particionado y selección de particiones
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/partition.sh" ]; then
    source "$SCRIPT_DIR/partition.sh"
else
    echo -e "${ROJO}[ERROR] No se encontró el script de particionado: $SCRIPT_DIR/partition.sh${RESET}"
    exit 1
fi

# 7. Desmontar particiones previas si existiesen
echo -e "\n${VERDE}[+] Limpiando montajes previos...${RESET}"
swapoff -a || true
umount -R /mnt 2>/dev/null || true

# 8. Particionado automático (solo en modo automático)
if [ "$PARTITION_MODE" == "1" ]; then
    echo -e "${VERDE}[+] Particionando automáticamente el disco $TARGET_DISK con sgdisk...${RESET}"
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
fi

# 9. Formatear particiones
echo -e "\n${VERDE}[+] Preparando sistemas de archivos...${RESET}"
if [ "$FORMAT_EFI" == "si" ]; then
    echo -e "${VERDE}[+] Formateando partición EFI ($PART_EFI) en FAT32...${RESET}"
    mkfs.fat -F 32 -n "EFI" "$PART_EFI"
else
    echo -e "${AZUL}[*] Conservando partición EFI ($PART_EFI) sin formatear.${RESET}"
fi

if [ -n "$PART_SWAP" ]; then
    echo -e "${VERDE}[+] Formateando partición SWAP ($PART_SWAP)...${RESET}"
    mkswap -L "SWAP" "$PART_SWAP"
fi

echo -e "${VERDE}[+] Formateando partición ROOT ($PART_ROOT) en ext4...${RESET}"
mkfs.ext4 -F -L "ARCH_ROOT" "$PART_ROOT"

# 10. Montar el sistema de archivos
echo -e "\n${VERDE}[+] Montando particiones en /mnt...${RESET}"
mount "$PART_ROOT" /mnt
mount --mkdir "$PART_EFI" /mnt/boot

if [ -n "$PART_SWAP" ]; then
    echo -e "${VERDE}[+] Activando SWAP en $PART_SWAP...${RESET}"
    swapon "$PART_SWAP"
fi

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
pacman -S --noconfirm grub efibootmgr os-prober

# Habilitar detección de otros sistemas operativos en GRUB (Dual-Boot)
if grep -q "^# *GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    sed -i 's/^# *GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
elif ! grep -q "^GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

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
