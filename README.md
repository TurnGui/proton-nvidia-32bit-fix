# Linux Steam fixes for older Windows games via Proton

This repository contains two scripts to solve the most common problems when running older 32-bit Windows games (e.g., Shogun 2, OG Skyrim, Half-Life 2, Fallout 3/NV, Dragon Age Origins, GTA IV) through Proton on modern Ubuntu based systems.

If you prefer I made a video tutorial using both of these scripts here:  
[YouTube: Fix Shogun 2 & Other 32-bit Steam Games on Linux Mint NVIDIA (llvmpipe Fix)](https://www.youtube.com/watch?v=5TS-7SwusPY)

### Included scripts:

1. **`nvidia-32bit-fix.sh`** — Fixes NVIDIA GPU detection for 32-bit games on Ubuntu/Mint with driver 550+, especially on RTX 30/40/50 series. Use this if your game shows a black screen or defaults to `llvmpipe` (software rendering).
2. **`proton-game-fix.sh`** — Installs missing Windows runtime libraries (Visual C++ Redistributables, .NET, etc.) into a specific game’s Proton prefix. Use this if your game crashes at the launcher or hangs at startup, but your GPU is detected correctly.

If you’re not sure which problem you have, try them in order. They’re independent; running one won’t interfere with the other.

---

### Script 1: `nvidia-32bit-fix.sh`

**Who needs this:**  
- Ubuntu 24.04 (or Mint 22.x/Pop!_OS 24.04)  
- RTX 30/40/50-series with NVIDIA drivers 550+  
- 32-bit Windows games via Proton crash, black screen, or run unusably slow  
- DXVK/D3D11 logs show `"Device name: llvmpipe"` instead of NVIDIA
---

On **Arch**, **Fedora**, and **openSUSE**, install your distro's 32-bit NVIDIA libraries (`lib32-nvidia-utils` or equivalent) instead; or so i heard, i cant really test that myself but this script isnt for you im sorry :(

---

**What’s going on:**  
Ubuntu stopped packaging the 32-bit NVIDIA driver libs (`libnvidia-gl-*:i386`) starting with driver 550. The 64-bit side works, but 32-bit Vulkan apps—including many games through Proton can’t find your GPU. They fall back to llvmpipe (which is just the CPU doing slow software rendering).

**What this script does:**  
- Checks your driver/install state and whether the problem applies to your setup.
- Downloads the right NVIDIA installer and extracts only the 32-bit libs.
- Installs those to `/usr/lib/i386-linux-gnu/`, creates the right symlinks, and registers the 32-bit Vulkan ICD.
- Asks for confirmation before making changes; stops on any error.
- Doesn’t touch your kernel modules, driver config, or system-wide 64-bit libraries.

**How to use:**  
- Read the script before running (`less nvidia-32bit-fix.sh`)
- Make it executable: `chmod +x nvidia-32bit-fix.sh`
- (Optional) Dry-run mode: `./nvidia-32bit-fix.sh --dry-run`
- Run with `./nvidia-32bit-fix.sh`
- Takes about 1–2 minutes (most of it downloading the NVIDIA installer).

**After running:**  
Re-launch your game and check the log again. If “Device name” is now your actual NVIDIA GPU, rendering should work as intended. If it still crashes, you’re likely missing Windows runtime libraries—see Script 2.

**Driver upgrades:**  
Re-run this script after upgrading NVIDIA drivers. The 64-bit/apt and 32-bit/manual pieces need to match.

**To undo:**  
See the script or README “Reverting” section. Only remove the specific NVIDIA 32-bit libs and config added; don’t mess with Mesa libs or you’ll break Steam. If you accidentally remove core Mesa bits, reinstall them with apt as described.

---
### Script 2: `proton-game-fix.sh`

This script installs required Windows runtime libraries (Visual C++ Redistributables, .NET Framework, DirectX, etc.) into a specific game’s Proton prefix using `protontricks`. It’s the common solution for older Windows games that start but either crash, hang, or don’t launch fully—even after the GPU is detected properly.

**When to use this:**
- You’re running an older 32-bit (or sometimes 64-bit) Windows game through Proton.
- The video card is detected (DXVK log shows your actual GPU, not llvmpipe).
- The game either crashes on startup, hangs at a launcher, or fails to launch.
- You’ve already resolved graphics/driver issues (see Script 1) and the problem persists.

**What does this script do:**
- Locates your Steam library (works with typical native paths, Flatpak Steam, as well as additional libraries).
- Installs `protontricks` via Flatpak if it’s not already present. (The Flatpak version works reliably with current Steam; the apt package does not.)
- Prompts you to search for and select your game from your installed library.
- Matches your game against a known list of required components when possible (for popular titles).
- If no match is found, suggests commonly-needed packages or allows manual entry.
- Shows a summary and asks for confirmation.
- Runs `protontricks` to install the necessary runtime libraries for that game’s Proton prefix.

**Usage:**

```bash
# Review the script first.
less proton-game-fix.sh

# Make it executable.
chmod +x proton-game-fix.sh

# (Optional) See what it will do without any changes.
./proton-game-fix.sh --dry-run

# Run the actual fix:
./proton-game-fix.sh
```

**What to know:**
- The script is interactive; it won’t change anything without your confirmation.
- No root/sudo required; only operates in your user’s home and Flatpak.
- Make sure the game is not running (including background processes in Steam) before starting, or `protontricks` will refuse to modify the prefix.
- If the libraries install successfully but the game still fails:  
  - Check [ProtonDB](https://protondb.com) for specific advice on your game. Many users share working configurations and exact fixes.
  - You can rerun this script and choose manual package entry if you find recommendations that differ.
  - Sometimes switching to a community Proton build (like GE-Proton, via [ProtonUp-Qt](https://flathub.org/apps/net.davidotek.pupgui2)) is needed. Select it in the game's Properties → Compatibility tab if troubleshooting with extra Proton versions.

---

## Troubleshooting & Extra Notes

- **After using script 1 (nvidia-32bit-fix.sh):**  
  If you still see performance issues or crashes, but your GPU is now detected, you’re most likely missing Windows runtime libs—use script 2.
- **Removing changes:**  
  Detailed removal steps are documented in the relevant section above. Only remove files placed by the script, not the base system libraries, to avoid breaking Steam or desktop compositing.
- **Mesa package recovery (if needed):**  
  If you accidentally remove core 32-bit Mesa libraries, reinstall with:
  ```bash
  sudo apt install --reinstall libgl1:i386 libegl1:i386 libgles2:i386 \
                               libglx0:i386 libglvnd0:i386 libopengl0:i386
  ```

---

## Feedback

If you run into edge cases, have a system setup these scripts don’t cover, or find a more reliable way to solve these issues, contributions and suggestions are welcome. Open an issue or PR.

---

## References

- [ProtonDB](https://protondb.com)
- [Protontricks](https://github.com/Matoking/protontricks)
- [GE-Proton (ProtonUp-Qt)](https://flathub.org/apps/net.davidotek.pupgui2)
- [Valve’s Steam Play Documentation](https://github.com/ValveSoftware/Proton)
