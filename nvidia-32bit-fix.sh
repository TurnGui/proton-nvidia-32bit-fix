#!/usr/bin/env bash
#
# nvidia-32bit-fix.sh
#
# Installs NVIDIA 32-bit libraries on Ubuntu 24.04 / Linux Mint 22.x systems
# where they are missing from the apt repos (driver 550+ and newer).
#
# This fixes a common problem where 32-bit games running through Proton
# (Steam Play) fall back to llvmpipe (CPU rendering) because Vulkan can't
# find a 32-bit NVIDIA ICD. Symptom: black screens, crashes on launch,
# or extremely poor performance with games like Total War: Shogun 2,
# Skyrim Original, Half-Life 2, and other older titles.
#
# What it does:
#   1. Detects if you actually have this problem (skips otherwise).
#   2. Downloads the official NVIDIA .run installer matching your driver.
#   3. Extracts only the 32-bit libraries (does NOT install the driver).
#   4. Copies them to /usr/lib/i386-linux-gnu/.
#   5. Creates the symlinks applications expect.
#   6. Registers a 32-bit Vulkan ICD at /usr/share/vulkan/icd.d/.
#   7. Refreshes the dynamic linker cache.
#
# What it does NOT do:
#   - Touch your installed NVIDIA driver.
#   - Modify any kernel modules.
#   - Replace existing 64-bit libraries.
#   - Change anything outside /usr/lib/i386-linux-gnu/ and /usr/share/vulkan/icd.d/.
#
# Run with --dry-run to see exactly what it would do without doing anything.
# Run with --help for usage info.
#
# License: public domain. Use at your own risk. Read the script before running it.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly TARGET_LIB_DIR="/usr/lib/i386-linux-gnu"
readonly VULKAN_ICD_DIR="/usr/share/vulkan/icd.d"
readonly ICD_FILE="${VULKAN_ICD_DIR}/nvidia_icd.i686.json"
readonly TMP_DIR="${TMPDIR:-/tmp}/nvidia-32bit-fix-$$"

if [[ -t 1 ]]; then
    readonly C_RED=$'\033[0;31m'
    readonly C_GREEN=$'\033[0;32m'
    readonly C_YELLOW=$'\033[0;33m'
    readonly C_BLUE=$'\033[0;34m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RESET=$'\033[0m'
else
    readonly C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD="" C_RESET=""
fi

DRY_RUN=0
ASSUME_YES=0
DRIVER_VERSION=""
VULKAN_API_VERSION=""

info()  { echo "${C_BLUE}[info]${C_RESET} $*"; }
ok()    { echo "${C_GREEN}[ ok ]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[warn]${C_RESET} $*" >&2; }
err()   { echo "${C_RED}[err ]${C_RESET} $*" >&2; }
step()  { echo; echo "${C_BOLD}==> $*${C_RESET}"; }

run() {
    # Wrapper: prints command, runs it (or skips if dry-run).
    echo "    ${C_BOLD}\$${C_RESET} $*"
    if [[ $DRY_RUN -eq 0 ]]; then
        "$@"
    fi
}

run_sudo() {
    echo "    ${C_BOLD}\$${C_RESET} sudo $*"
    if [[ $DRY_RUN -eq 0 ]]; then
        sudo "$@"
    fi
}

usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} — install NVIDIA 32-bit libs on Ubuntu/Mint

Usage:
  ${SCRIPT_NAME} [--dry-run] [--yes] [--help]

Options:
  --dry-run   Show every command that would be run, but do not execute anything
              that modifies the system. Safe to run on any machine.
  --yes       Skip the final confirmation prompt. Useful for automation.
              You should still run with --dry-run first to review.
  --help      Show this help.

Run without options for the normal interactive mode.

This script needs sudo for: copying libs to /usr/lib/i386-linux-gnu/,
creating symlinks there, writing /usr/share/vulkan/icd.d/nvidia_icd.i686.json,
and running ldconfig. It does not need sudo for anything else.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) err "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY RUN — no changes will be made to the system."
fi

# Running the whole script as root is unnecessary and dangerous; we want sudo
# only on the specific commands that need it, so a stray bug can't nuke the
# system.
if [[ ${EUID} -eq 0 ]]; then
    err "Do not run this script as root or with sudo. It will call sudo itself"
    err "only for the specific commands that need it."
    exit 1
fi

step "Checking your system…"

# 1. Is this Ubuntu/Mint/Debian-based?
if ! command -v apt >/dev/null 2>&1; then
    err "This script is only for Debian/Ubuntu/Mint systems (apt-based)."
    exit 1
fi
ok "Debian/Ubuntu/Mint-based system detected."

# 2. Is i386 architecture enabled?
if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    err "i386 architecture is not enabled. Run:"
    err "    sudo dpkg --add-architecture i386 && sudo apt update"
    err "Then re-run this script."
    exit 1
fi
ok "i386 architecture is enabled."

# 3. Is there an NVIDIA GPU with a working driver?
if ! command -v nvidia-smi >/dev/null 2>&1; then
    err "nvidia-smi not found — is the NVIDIA proprietary driver installed?"
    err "Use Driver Manager (in Mint) or 'ubuntu-drivers autoinstall' first."
    exit 1
fi

if ! DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)"; then
    err "Could not query driver version from nvidia-smi. Is the GPU active?"
    exit 1
fi
DRIVER_VERSION="${DRIVER_VERSION// /}"
if [[ -z "$DRIVER_VERSION" ]]; then
    err "nvidia-smi returned an empty driver version."
    exit 1
fi
ok "NVIDIA driver detected: ${C_BOLD}${DRIVER_VERSION}${C_RESET}"

# 4. Are 32-bit NVIDIA libs already present?
# We look for a few key ones: libGLX_nvidia.so.0 and libnvidia-glcore.so
# If they exist, the user probably already has this fixed (or installed via
# the legacy 470 driver). We err on the side of not running again.
existing_libs=0
for lib in libGLX_nvidia.so.0 libEGL_nvidia.so.0 libnvidia-glcore.so.1; do
    if [[ -e "${TARGET_LIB_DIR}/${lib}" ]]; then
        existing_libs=$((existing_libs + 1))
    fi
done

icd_present=0
if [[ -e "${ICD_FILE}" ]]; then
    icd_present=1
fi

if [[ $existing_libs -ge 3 && $icd_present -eq 1 ]]; then
    warn "It looks like 32-bit NVIDIA libs and the Vulkan ICD are already installed."
    warn "If your games are still broken, the issue is probably elsewhere"
    warn "(missing protontricks redists, wrong Proton version, etc.)."
    warn ""
    warn "If you want to reinstall anyway (e.g. after a driver update),"
    warn "you can continue. Existing files will be overwritten."
    if [[ $ASSUME_YES -eq 0 ]]; then
        read -rp "Continue anyway? [y/N] " ans
        case "${ans,,}" in
            y|yes) : ;;
            *) info "Aborted by user. Nothing was changed."; exit 0 ;;
        esac
    fi
elif [[ $existing_libs -gt 0 || $icd_present -eq 1 ]]; then
    warn "Partial install detected — some 32-bit NVIDIA files are present but"
    warn "not all. This script will fill in the gaps and overwrite anything"
    warn "that's stale."
else
    ok "32-bit NVIDIA libraries are missing — this is the problem the script fixes."
fi

# 5. Detect Vulkan API version from the existing 64-bit ICD, so the new
# 32-bit ICD reports a sensible value. Falls back to a safe default.
if [[ -e "${VULKAN_ICD_DIR}/nvidia_icd.json" ]]; then
    VULKAN_API_VERSION="$(grep -oE '"api_version"[[:space:]]*:[[:space:]]*"[^"]+"' \
        "${VULKAN_ICD_DIR}/nvidia_icd.json" 2>/dev/null \
        | head -n1 | grep -oE '"[0-9.]+"$' | tr -d '"' || true)"
fi
if [[ -z "$VULKAN_API_VERSION" ]]; then
    VULKAN_API_VERSION="1.3.0"
    warn "Could not read Vulkan API version from existing 64-bit ICD; using default ${VULKAN_API_VERSION}."
else
    ok "Vulkan API version (from 64-bit ICD): ${VULKAN_API_VERSION}"
fi

RUN_FILE="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
RUN_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/${RUN_FILE}"
EXTRACT_DIR="${TMP_DIR}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}"

step "Plan"
cat <<EOF
This script will:
  1. Download ${C_BOLD}${RUN_URL}${C_RESET}
     into ${TMP_DIR}/ (a temp directory; ~400 MB).
  2. Extract it (no system install) and copy ONLY the 32-bit .so files
     from its 32/ subfolder to ${C_BOLD}${TARGET_LIB_DIR}/${C_RESET}.
  3. Create the symlinks (libGLX_nvidia.so.0, libEGL_nvidia.so.0, etc.)
     that applications and DXVK expect.
  4. Write a Vulkan ICD pointer to ${C_BOLD}${ICD_FILE}${C_RESET}
     so 32-bit Vulkan apps can find the NVIDIA driver.
  5. Run ${C_BOLD}sudo ldconfig${C_RESET} to refresh the linker cache.
  6. Clean up ${TMP_DIR}/ at the end (you can keep it with --keep-tmp; not implemented yet).

It will NOT modify your kernel modules, your installed driver, your X config,
or anything outside ${TARGET_LIB_DIR}/ and ${VULKAN_ICD_DIR}/.

If the existing ${ICD_FILE} is present, it will be backed up to
${ICD_FILE}.bak.<timestamp> before being overwritten.
EOF

if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
    echo
    read -rp "Proceed? [y/N] " ans
    case "${ans,,}" in
        y|yes) : ;;
        *) info "Aborted by user. Nothing was changed."; exit 0 ;;
    esac
fi

cleanup() {
    if [[ -d "$TMP_DIR" && $DRY_RUN -eq 0 ]]; then
        info "Cleaning up ${TMP_DIR}/"
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

step "Step 1/5: Download the NVIDIA .run installer"

run mkdir -p "$TMP_DIR"

if command -v curl >/dev/null 2>&1; then
    run curl -fL --progress-bar -o "${TMP_DIR}/${RUN_FILE}" "${RUN_URL}"
elif command -v wget >/dev/null 2>&1; then
    run wget --show-progress -O "${TMP_DIR}/${RUN_FILE}" "${RUN_URL}"
else
    err "Neither curl nor wget is installed. Install one and retry:"
    err "    sudo apt install curl"
    exit 1
fi

if [[ $DRY_RUN -eq 0 ]]; then
    if [[ ! -s "${TMP_DIR}/${RUN_FILE}" ]]; then
        err "Download failed or file is empty. URL may have changed for driver ${DRIVER_VERSION}."
        err "Check https://www.nvidia.com/en-us/drivers/ for the correct .run file."
        exit 1
    fi
    file_size=$(stat -c %s "${TMP_DIR}/${RUN_FILE}" 2>/dev/null || echo 0)
    if [[ $file_size -lt 100000000 ]]; then
        err "Downloaded file is only ${file_size} bytes — that's too small to be a real driver."
        err "URL: ${RUN_URL}"
        exit 1
    fi
    ok "Downloaded $(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size} bytes")."
fi

step "Step 2/5: Extract (no install)"

run chmod +x "${TMP_DIR}/${RUN_FILE}"
# The .run extracts into the current directory. We do it inside TMP_DIR so it's
# self-contained and gets cleaned up on exit.
run bash -c "cd '${TMP_DIR}' && './${RUN_FILE}' --extract-only"

if [[ $DRY_RUN -eq 0 ]]; then
    if [[ ! -d "${EXTRACT_DIR}/32" ]]; then
        err "Expected ${EXTRACT_DIR}/32/ to exist after extraction, but it doesn't."
        err "The .run installer may have changed format, or the driver version"
        err "${DRIVER_VERSION} may not ship 32-bit files."
        exit 1
    fi

    # Sanity: count expected files
    so_count=$(find "${EXTRACT_DIR}/32" -maxdepth 1 -name "*.so*" -type f | wc -l)
    if [[ $so_count -lt 5 ]]; then
        err "Only ${so_count} .so files found in ${EXTRACT_DIR}/32/ — expected many more."
        err "Aborting before doing anything to /usr/lib/i386-linux-gnu/."
        exit 1
    fi
    ok "Extracted; ${so_count} 32-bit .so files found."
fi

step "Step 3/5: Install 32-bit libraries to ${TARGET_LIB_DIR}/"

# -P preserves symlinks (some files in 32/ are themselves links).
run_sudo cp -P "${EXTRACT_DIR}/32/"*.so* "${TARGET_LIB_DIR}/"

step "    Creating symlinks…"

# Each entry: "<symlink>:<target>". Target must be the actual file we just
# copied. We use the driver version we detected, so this works for any version.
declare -a SYMLINKS=(
    "libGLX_nvidia.so.0:libGLX_nvidia.so.${DRIVER_VERSION}"
    "libEGL_nvidia.so.0:libEGL_nvidia.so.${DRIVER_VERSION}"
    "libEGL.so.1:libEGL.so.1.1.0"
    "libEGL.so:libEGL.so.1"
    "libGL.so.1:libGL.so.1.7.0"
    "libGL.so:libGL.so.1"
    "libGLX.so:libGLX.so.0"
    "libGLESv1_CM.so.1:libGLESv1_CM.so.1.2.0"
    "libGLESv1_CM_nvidia.so.1:libGLESv1_CM_nvidia.so.${DRIVER_VERSION}"
    "libGLESv2.so.2:libGLESv2.so.2.1.0"
    "libGLESv2_nvidia.so.2:libGLESv2_nvidia.so.${DRIVER_VERSION}"
    "libnvidia-glcore.so.1:libnvidia-glcore.so.${DRIVER_VERSION}"
    "libnvidia-tls.so.1:libnvidia-tls.so.${DRIVER_VERSION}"
    "libnvidia-glsi.so.0:libnvidia-glsi.so.${DRIVER_VERSION}"
    "libnvidia-glvkspirv.so:libnvidia-glvkspirv.so.${DRIVER_VERSION}"
    "libcuda.so.1:libcuda.so.${DRIVER_VERSION}"
    "libcuda.so:libcuda.so.1"
)

for entry in "${SYMLINKS[@]}"; do
    link="${entry%%:*}"
    target="${entry##*:}"
    # Skip if the target file isn't actually present (e.g. older driver
    # versions that don't ship that lib). Avoids creating dangling symlinks.
    if [[ $DRY_RUN -eq 0 && ! -e "${TARGET_LIB_DIR}/${target}" ]]; then
        warn "Skipping symlink ${link} -> ${target} (target file not present)."
        continue
    fi
    run_sudo ln -sf "${target}" "${TARGET_LIB_DIR}/${link}"
done

step "Step 4/5: Register the 32-bit Vulkan ICD"

if [[ -e "${ICD_FILE}" && $DRY_RUN -eq 0 ]]; then
    backup="${ICD_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    info "Backing up existing ${ICD_FILE} to ${backup}"
    run_sudo cp -a "${ICD_FILE}" "${backup}"
fi

ICD_CONTENT="{
    \"file_format_version\" : \"1.0.0\",
    \"ICD\": {
        \"library_path\": \"libGLX_nvidia.so.0\",
        \"api_version\" : \"${VULKAN_API_VERSION}\"
    }
}"

echo "    ${C_BOLD}\$${C_RESET} sudo tee ${ICD_FILE} <<< (Vulkan ICD JSON)"
if [[ $DRY_RUN -eq 0 ]]; then
    echo "${ICD_CONTENT}" | sudo tee "${ICD_FILE}" > /dev/null
fi

step "Step 5/5: Refresh the dynamic linker cache"
run_sudo ldconfig

step "All done."
ok "32-bit NVIDIA libs installed for driver ${DRIVER_VERSION}."

cat <<EOF

${C_BOLD}What to do now:${C_RESET}

  1. Launch your game through Steam (with Proton enabled).
  2. After it's running (or has crashed), check the game's d3d11/dxvk log
     for the active GPU. For Total War: Shogun 2:

     ${C_BOLD}grep "Device name" ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/shogun2_d3d11.log${C_RESET}

     It should now report your NVIDIA GPU, not 'llvmpipe'.

  3. If the game still doesn't run, the GPU is no longer the issue.
     Common other fixes for older Windows games via Proton:

       flatpak install flathub com.github.Matoking.protontricks
       flatpak override --user --filesystem=~/.steam com.github.Matoking.protontricks
       flatpak run --env=STEAM_DIR="\$HOME/.steam/debian-installation" \\
           com.github.Matoking.protontricks <APPID> -q \\
           d3dcompiler_47 vcrun2010 vcrun2013 vcrun2019 dotnet40

     (Replace <APPID> with the Steam app ID; e.g. 34330 for Shogun 2.)

${C_BOLD}When the NVIDIA driver updates:${C_RESET}
  Re-run this script. The apt-managed 64-bit libs will be at the new version
  but the 32-bit libs you installed manually will still be at ${DRIVER_VERSION}
  and will likely be incompatible. Re-running fetches the new .run and updates
  everything to match.
EOF
