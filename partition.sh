#!/usr/bin/env bash
# ==============================================================================
# MÓDULO DE PARTICIONADO Y SELECCIÓN DE PARTICIONES
# Proyecto: BTW_Arch
# ==============================================================================
# Este script define e inicializa las siguientes variables para la instalación:
#   - PARTITION_MODE ("1" = Automático, "2" = Existente / Manual)
#   - PART_EFI       (Ruta a la partición EFI, ej. /dev/sda1)
#   - FORMAT_EFI     ("si" o "no")
#   - PART_ROOT      (Ruta a la partición ROOT, ej. /dev/sda3)
#   - PART_SWAP      (Ruta a la partición SWAP, o vacío si se omite)
# Requiere:
#   - TARGET_DISK    (Dispositivo de almacenamiento seleccionado, ej. /dev/sda)
# ==============================================================================

set -euo pipefail

# Asegurar colores si se ejecuta o importa de forma independiente
VERDE="${VERDE:-\e[32m}"
AZUL="${AZUL:-\e[34m}"
AMARILLO="${AMARILLO:-\e[33m}"
ROJO="${ROJO:-\e[31m}"
RESET="${RESET:-\e[0m}"

PART_EFI=""
PART_SWAP=""
PART_ROOT=""
FORMAT_EFI="si"
PARTITION_MODE=""

echo -e "\n${AZUL}====================================================${RESET}"
echo -e "${AZUL}           MÉTODO DE PARTICIONADO                   ${RESET}"
echo -e "${AZUL}====================================================${RESET}"
echo -e "1) Particionado automático de todo el disco"
echo -e "   (${ROJO}¡Borra todo el contenido de $TARGET_DISK!${RESET} Crea EFI 1GB, Swap 4GB y Root)"
echo -e "2) Seleccionar particiones existentes en el disco / Particionado manual"
echo -e "   (Permite seleccionar particiones ya existentes o usar cfdisk sin borrar todo el disco)"

while true; do
    read -rp "Selecciona una opción [1 o 2]: " PARTITION_MODE
    if [[ "$PARTITION_MODE" == "1" || "$PARTITION_MODE" == "2" ]]; then
        break
    else
        echo -e "${ROJO}[!] Opción inválida. Elige 1 o 2.${RESET}"
    fi
done

if [ "$PARTITION_MODE" == "1" ]; then
    echo -e "\n${ROJO}====================================================${RESET}"
    echo -e "${ROJO}  ¡ADVERTENCIA: TODOS LOS DATOS EN $TARGET_DISK SERÁN BORRADOS!${RESET}"
    echo -e "${ROJO}====================================================${RESET}"
    read -rp "¿Estás completamente seguro de borrar todo el disco $TARGET_DISK? (escribe 'si' para proceder): " CONFIRM

    if [ "$CONFIRM" != "si" ]; then
        echo -e "${AMARILLO}[!] Instalación cancelada por el usuario.${RESET}"
        exit 0
    fi

    # Definir nomenclatura de particiones automáticas (SATA vs NVMe)
    if [[ "$TARGET_DISK" =~ nvme ]]; then
        PART_EFI="${TARGET_DISK}p1"
        PART_SWAP="${TARGET_DISK}p2"
        PART_ROOT="${TARGET_DISK}p3"
    else
        PART_EFI="${TARGET_DISK}1"
        PART_SWAP="${TARGET_DISK}2"
        PART_ROOT="${TARGET_DISK}3"
    fi
    FORMAT_EFI="si"
else
    # Opción 2: Particiones existentes / particionado manual
    echo -e "\n${AZUL}[*] Modo de particiones existentes seleccionado.${RESET}"

    # Ofrecer abrir cfdisk
    read -rp "¿Deseas abrir 'cfdisk' ahora para crear o ajustar particiones en $TARGET_DISK? [s/N]: " OPEN_CFDISK
    if [[ "$OPEN_CFDISK" =~ ^[sS]([iI])?$ ]]; then
        echo -e "${VERDE}[+] Abriendo cfdisk para $TARGET_DISK...${RESET}"
        cfdisk "$TARGET_DISK"
        partprobe "$TARGET_DISK" 2>/dev/null || true
        sleep 1
    fi

    echo -e "\n${AZUL}[*] Particiones detectadas en el disco $TARGET_DISK:${RESET}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$TARGET_DISK"
    echo ""

    # Función auxiliar para solicitar y validar una partición
    solicitar_particion() {
        local -n _dest_var="$1"
        local _prompt_text="$2"
        local _obligatoria="$3"
        local _selected=""

        while true; do
            read -rp "$_prompt_text" _selected
            _selected="${_selected#"${_selected%%[![:space:]]*}"}"
            _selected="${_selected%"${_selected##*[![:space:]]}"}"

            if [ -z "$_selected" ]; then
                if [ "$_obligatoria" = "false" ]; then
                    _dest_var=""
                    return 0
                else
                    echo -e "${ROJO}[!] Esta partición es obligatoria. Por favor ingresa un valor.${RESET}"
                    continue
                fi
            fi

            if [ "$_obligatoria" = "false" ] && [[ "$_selected" =~ ^(ninguna|ninguno|none|no)$ ]]; then
                _dest_var=""
                return 0
            fi

            if [[ ! "$_selected" =~ ^/dev/ ]]; then
                _selected="/dev/${_selected}"
            fi

            if [ -b "$_selected" ]; then
                _dest_var="$_selected"
                return 0
            else
                echo -e "${ROJO}[ERROR] El dispositivo '$_selected' no existe o no es válido.${RESET}"
            fi
        done
    }

    echo -e "${VERDE}--> Configuración de partición ROOT (Sistema principal /)${RESET}"
    echo -e "${ROJO}ADVERTENCIA: Esta partición SÍ será formateada en ext4.${RESET}"
    solicitar_particion PART_ROOT "Ingresa la partición ROOT (ejemplo: ${TARGET_DISK}3 o ${TARGET_DISK}p3): " "true"

    echo -e "\n${VERDE}--> Configuración de partición EFI (Arranque UEFI)${RESET}"
    echo -e "Nota: Debe ser partición tipo EFI System (FAT32, recomendada de 512MB a 1GB)."
    solicitar_particion PART_EFI "Ingresa la partición EFI (ejemplo: ${TARGET_DISK}1 o ${TARGET_DISK}p1): " "true"
    while [ "$PART_EFI" == "$PART_ROOT" ]; do
        echo -e "${ROJO}[!] La partición EFI no puede ser la misma que la ROOT.${RESET}"
        solicitar_particion PART_EFI "Ingresa una partición EFI distinta: " "true"
    done

    echo -e "\n${AMARILLO}[?] ¿Deseas formatear la partición EFI ($PART_EFI) en FAT32?${RESET}"
    echo -e "    - Escribe 'si' para formatearla (Recomendado en instalación limpia)."
    echo -e "    - Escribe 'no' si ya tienes Windows u otro sistema y deseas conservar el arranque dual."
    read -rp "¿Formatear partición EFI? [si/no] (por defecto: no): " RESP_FORMAT_EFI
    if [[ "$RESP_FORMAT_EFI" =~ ^[sS]([iI])?$ ]]; then
        FORMAT_EFI="si"
    else
        FORMAT_EFI="no"
    fi

    echo -e "\n${VERDE}--> Configuración de partición SWAP (Memoria de intercambio)${RESET}"
    echo -e "Nota: Opcional. Presiona Enter o escribe 'ninguna' si prefieres omitir swap o usar swapfile/zram."
    solicitar_particion PART_SWAP "Ingresa la partición SWAP (o presiona Enter para omitir): " "false"
    if [ -n "$PART_SWAP" ]; then
        while [[ "$PART_SWAP" == "$PART_EFI" || "$PART_SWAP" == "$PART_ROOT" ]]; do
            echo -e "${ROJO}[!] La partición SWAP no puede ser igual a EFI ni a ROOT.${RESET}"
            solicitar_particion PART_SWAP "Ingresa una partición SWAP distinta (o Enter para omitir): " "false"
            [ -z "$PART_SWAP" ] && break
        done
    fi

    echo -e "\n${AZUL}====================================================${RESET}"
    echo -e "${AZUL}      RESUMEN DE PARTICIONES SELECCIONADAS         ${RESET}"
    echo -e "${AZUL}====================================================${RESET}"
    echo -e "Partición ROOT: ${VERDE}${PART_ROOT}${RESET} (${ROJO}Será formateada en ext4${RESET})"
    if [ "$FORMAT_EFI" == "si" ]; then
        echo -e "Partición EFI:  ${VERDE}${PART_EFI}${RESET} (${ROJO}Será formateada en FAT32${RESET})"
    else
        echo -e "Partición EFI:  ${VERDE}${PART_EFI}${RESET} (${VERDE}Se conservará sin formatear${RESET})"
    fi
    if [ -n "$PART_SWAP" ]; then
        echo -e "Partición SWAP: ${VERDE}${PART_SWAP}${RESET} (Será formateada y activada)"
    else
        echo -e "Partición SWAP: ${AMARILLO}Ninguna (Omitida)${RESET}"
    fi
    echo -e "${AZUL}====================================================${RESET}"

    read -rp "¿Confirmas que los datos son correctos para proceder? (escribe 'si' para continuar): " CONFIRM_EXISTING
    if [ "$CONFIRM_EXISTING" != "si" ]; then
        echo -e "${AMARILLO}[!] Instalación cancelada por el usuario.${RESET}"
        exit 0
    fi
fi
