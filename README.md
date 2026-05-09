# Linux Steam fixes for older Windows games via Proton

Two scripts that fix the most common reasons older 32-bit Windows games
(Total War: Shogun 2, Skyrim Original, Half-Life 2, Fallout 3/NV, Dragon
Age Origins, GTA IV, etc.) crash or refuse to launch on modern Linux setups
via Proton:

1. **`nvidia-32bit-fix.sh`** — fixes NVIDIA GPU detection for 32-bit games
   on Ubuntu/Mint (driver 550+). Most likely the fix you need if you're on
   an RTX 30/40/50-series card and your game black-screens or hits
   `llvmpipe` software rendering.

2. **`proton-game-fix.sh`** — installs the Windows runtime libraries
   (Visual C++ Redistributables, .NET, etc.) that older games need, into
   the specific game's Proton prefix. Most likely the fix you need if your
   game crashes at the launcher or hangs on startup, even though the GPU
   itself is fine.

If you're not sure which you need, run them in that order. Each one is
safe to run on its own and they don't interfere with each other.

---

## Script 1: `nvidia-32bit-fix.sh`

Installs NVIDIA 32-bit libraries on Ubuntu 24.04 / Linux Mint 22.x when
they're missing from apt — fixing 32-bit Windows games (run via Proton)
that crash, black-screen, or fall back to software rendering on modern
NVIDIA GPUs.

### Who is this for?

You, if all of the following are true:

- You're on **Ubuntu 24.04 (Noble)** or a derivative (Linux Mint 22.x, Pop!_OS 24.04, etc.).
- You have a **modern NVIDIA GPU** (RTX 30/40/50-series) using **driver 550 or newer**.
- A **32-bit Windows game** running through **Proton** (Steam Play) crashes,
  black-screens, or runs at 5 FPS. Common culprits:
  Total War: Shogun 2, Empire/Napoleon Total War, Skyrim Original (not SE),
  Half-Life 2, Fallout 3/NV, Dragon Age Origins, GTA IV, etc.
- The game's DXVK log shows `Device name: llvmpipe (...)` instead of your
  NVIDIA GPU name. (See "How to verify the diagnosis" below.)

If you're on **Arch, Fedora, or openSUSE**, you don't need this script —
those distros package NVIDIA's 32-bit libs correctly. Install
`lib32-nvidia-utils` (Arch) or `xorg-x11-drv-nvidia-libs.i686` (Fedora) instead.

### What's the actual bug?

Starting with NVIDIA driver 550, **Ubuntu stopped packaging the 32-bit half
of the driver** (`libnvidia-gl-*:i386`). The 64-bit half installs fine, so
your desktop and 64-bit games work, but **32-bit Vulkan apps can't see the
GPU**. DXVK (Proton's DirectX-to-Vulkan layer) then falls back to `llvmpipe`,
which renders in CPU. Most games crash or are unplayable in this state.

NVIDIA still ships the 32-bit libs in its official `.run` installer — they're
just not in the apt repos. This script extracts them from the `.run` and
installs them by hand, without touching anything else.

### How to verify the diagnosis (before running anything)

For Total War: Shogun 2:

```bash
grep "Device name" ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/shogun2_d3d11.log
```

For other games, look for a `dxvk*.log` or `*_d3d11.log` file inside the
game's install folder, or run the game with `DXVK_LOG_LEVEL=info` and check
`~/.cache/dxvk/` or stdout.

If the device name is `llvmpipe`, this script is the right fix.
If it's already your NVIDIA GPU, the problem is somewhere else.

### Usage

```bash
# Read the script first. Always.
less nvidia-32bit-fix.sh

# Make it executable (downloaded scripts come without this bit set).
chmod +x nvidia-32bit-fix.sh

# Optional: see exactly what it would do, without doing anything.
./nvidia-32bit-fix.sh --dry-run

# Run for real.
./nvidia-32bit-fix.sh
```

The script will:

1. Check you have an NVIDIA driver, i386 enabled, and that this fix is
   actually needed.
2. Show you a plan of every action it'll take.
3. Ask for confirmation before doing anything.
4. Download the matching `.run` installer from `us.download.nvidia.com`.
5. Extract only the 32-bit libs (no driver install).
6. Copy them to `/usr/lib/i386-linux-gnu/` and create the expected symlinks.
7. Register a 32-bit Vulkan ICD at `/usr/share/vulkan/icd.d/nvidia_icd.i686.json`.
8. Run `ldconfig` to refresh the linker cache.

The whole thing takes 1–2 minutes (most of it is the 400 MB download).

### What the script will NOT do

- It won't replace your installed driver.
- It won't touch kernel modules or X config.
- It won't modify any 64-bit libraries.
- It won't touch anything outside `/usr/lib/i386-linux-gnu/` and
  `/usr/share/vulkan/icd.d/`.
- It won't run as root — it calls `sudo` itself, only for the specific
  commands that need root.
- It won't continue past any failed step. If something looks wrong, it stops.

If the existing `/usr/share/vulkan/icd.d/nvidia_icd.i686.json` is present,
it gets backed up to `nvidia_icd.i686.json.bak.<timestamp>` before being
overwritten.

### After running it

Re-launch your game. Check the d3d11/dxvk log again:

```bash
grep "Device name" ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/shogun2_d3d11.log
```

It should now report your NVIDIA GPU.

If the device name is now your NVIDIA GPU but the game **still** crashes or
won't launch, the 32-bit GPU problem is fixed and you're hitting a separate
issue: **the game is missing Windows runtime libraries** (Visual C++
Redistributables, .NET Framework, DirectX runtimes, etc.) that real Windows
ships with but that Proton's "fake Windows" does not.

That's exactly what Script 2 below is for.

### When the NVIDIA driver updates

Re-run the script. The 64-bit libs in apt will be at the new version, but
the 32-bit libs you installed manually are still at the old version, and
will likely break. Re-running fetches the new `.run` and updates everything
to match.

### Reverting

If for any reason you want to undo what this script did:

```bash
# Remove only the NVIDIA-specific 32-bit libraries.
# (Don't remove generic GL/EGL/GLX libraries — those belong to Mesa
# and the system uses them. Removing them will break your Steam client
# and possibly other apps.)
sudo rm -f /usr/lib/i386-linux-gnu/libGLX_nvidia.so* \
           /usr/lib/i386-linux-gnu/libEGL_nvidia.so* \
           /usr/lib/i386-linux-gnu/libGLESv*_nvidia.so* \
           /usr/lib/i386-linux-gnu/libnvidia-*.so* \
           /usr/lib/i386-linux-gnu/libcuda.so* \
           /usr/lib/i386-linux-gnu/libnvcuvid.so* \
           /usr/lib/i386-linux-gnu/libvdpau_nvidia.so*

# Remove the 32-bit Vulkan ICD (and any backups the script made)
sudo rm -f /usr/share/vulkan/icd.d/nvidia_icd.i686.json
sudo rm -f /usr/share/vulkan/icd.d/nvidia_icd.i686.json.bak.*

# Refresh the linker cache
sudo ldconfig
```

This puts you back exactly where you were before — 32-bit games will fall
back to `llvmpipe` (software rendering), but the system itself is intact.

> ⚠️ **Do NOT extend the `rm` list with files like `libGL.so*`, `libEGL.so*`,
> `libGLX.so*`, `libGLESv*.so*` (without `_nvidia`), `libGLdispatch.so*`,
> `libOpenGL.so*`, or `libOpenCL.so*`. Those are generic libraries provided
> by Mesa/glvnd that the system needs for Steam itself, your desktop, and
> non-NVIDIA apps. The script copies NVIDIA's versions on top of them, but
> the originals must remain installed via apt — removing them breaks
> Steam ("missing 32-bit libraries: libGL.so.1") and other apps.**
>
> If you accidentally removed those, you can fix it by reinstalling the
> Mesa packages:
>
> ```bash
> sudo apt install --reinstall libgl1:i386 libegl1:i386 libgles2:i386 \
>                              libglx0:i386 libglvnd0:i386 libopengl0:i386
> ```

---

## Script 2: `proton-game-fix.sh`

Installs Windows runtime libraries (Visual C++ Redistributables, .NET
Framework, DirectX runtimes, etc.) into a specific Steam game's Proton
prefix using `protontricks`. This is the standard fix for older Windows
games that crash on launch, fail to start, or hang at the launcher when
running through Proton on Linux.

This is the most common fix needed for games on Linux **after** the GPU is
working correctly. Each Steam game has its own isolated Proton environment
and needs its own runtimes installed — so this has to be done once per game.

### Who is this for?

You, if:

- You're running a 32-bit (or older 64-bit) Windows game through Proton.
- The game crashes at launch, fails to start, or hangs at the launcher
  splash screen.
- You're confident the GPU isn't the problem (i.e. you don't have an
  NVIDIA setup that needs Script 1, OR you've already run Script 1 and
  the game still doesn't work).

### Usage

```bash
# Read it first.
less proton-game-fix.sh

# Make it executable.
chmod +x proton-game-fix.sh

# Optional dry-run.
./proton-game-fix.sh --dry-run

# Run for real.
./proton-game-fix.sh
```

The script is interactive. It will:

1. Auto-detect where Steam is installed (handles `~/.steam/debian-installation`,
   `~/.local/share/Steam`, the Flatpak version, and Steam libraries on
   other drives).
2. Install `protontricks` via Flatpak if it's not already present.
   (It uses Flatpak rather than the apt version because the apt version
   doesn't work with current Steam app info format.)
3. Ask you to type part of the game's name. Searches your installed Steam
   library and shows matches.
4. Look up the game in its built-in list of known-good components for
   popular older games (Total War series, Bethesda games, Half-Life 2,
   GTA IV, BioShock, etc.). If the game isn't on the list, offers a
   sensible generic set or lets you enter your own.
5. Show you the plan and ask for confirmation.
6. Run protontricks to install the components into the game's prefix.

### What the script will NOT do

- It won't touch any system files (no sudo).
- It won't modify Proton itself, your driver, kernel modules, or anything
  outside `~/.steam/` and `~/.local/share/flatpak/`.
- It won't install components for a game without your confirmation.
- It won't continue past a failed step.

### Common pitfall

Make sure the game is **not running** (not even showing as "running" in
your Steam library) before running this script. Protontricks refuses to
operate on a prefix that's actively in use.

### What if the game still doesn't work?

If components install successfully but the game still crashes, check
**ProtonDB** (<https://protondb.com>) — search for your game and read recent
reports. People often paste the exact protontricks command that worked for
them. You can re-run this script and pick "enter your own components" to
use what you found.

Also worth trying: a different Proton version. **GE-Proton** (a community
fork with extra fixes) often works for older games where the official
Proton fails. Install it via [ProtonUp-Qt](https://flathub.org/apps/net.davidotek.pupgui2)
and select it in the game's Properties → Compatibility tab.

---

## License

Public domain. Read the script before running it. No warranty.
