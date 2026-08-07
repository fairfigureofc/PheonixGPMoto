#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
FIRMWARE_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="${FIRMWARE_DIR}/.pio/build/e32r28t"
PLATFORMIO_DIR="${PLATFORMIO_CORE_DIR:-${HOME}/.platformio}"
if [[ -n "${1:-}" ]]; then
  PORT="$1"
else
  serial_ports=(
    /dev/cu.usbserial*(N)
    /dev/cu.SLAB_USBtoUART*(N)
    /dev/cu.wchusbserial*(N)
    /dev/cu.usbmodem*(N)
  )
  if (( ${#serial_ports[@]} != 1 )); then
    echo "Connect one ESP32 over USB, then run this task again."
    echo "Detected ${#serial_ports[@]} compatible serial ports."
    exit 1
  fi
  PORT="${serial_ports[1]}"
fi

required_files=(
  "${BUILD_DIR}/bootloader.bin"
  "${BUILD_DIR}/partitions.bin"
  "${BUILD_DIR}/firmware.bin"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing ${required_file}. Run the normal Build task once first."
    exit 1
  fi
done

echo "Uploading cached firmware to ${PORT}"

"${PLATFORMIO_DIR}/penv/bin/python" \
  "${PLATFORMIO_DIR}/packages/tool-esptoolpy/esptool.py" \
  --chip esp32 \
  --port "${PORT}" \
  --baud 115200 \
  --before default_reset \
  --after hard_reset \
  write_flash -z \
  --flash_mode dio \
  --flash_freq 40m \
  --flash_size 4MB \
  0x1000 "${BUILD_DIR}/bootloader.bin" \
  0x8000 "${BUILD_DIR}/partitions.bin" \
  0xe000 "${PLATFORMIO_DIR}/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin" \
  0x10000 "${BUILD_DIR}/firmware.bin"
