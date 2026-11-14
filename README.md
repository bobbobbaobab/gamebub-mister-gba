# MiSTer GBA core for Game Bub

An unofficial port of [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer) for the Game Bub Rev4 handheld. It loads from the SD card and supports stereo audio, cartridge saves, and four save-state slots. Use Game Bub firmware v1.1.0-beta3.

## Install

1. Download `gamebub-mister-gba-v0.1.0-rev4.zip` from the [latest release](https://github.com/bobbobbaobab/gamebub-mister-gba/releases/latest).
2. Extract it to the SD card root. The bitstream and three JSON files go in `/cores/Game-Bub.MisterGBA/`.
3. Select **Game Boy Advance (MiSTer)** from the handheld's core list and open a `.gba` ROM.

The core includes the Normmatt BIOS. To use your own 16 KiB BIOS dump, place it in the core folder as `gba_bios.bin`.

In **Core Settings → Color Corrections**, choose **None**, **GBA** (default), **GBA SP**, **NDS**, **NDS Lite**, or **NSO GBA**. The setting applies to both the handheld display and HDMI output. Enable **LCD Pixel Grid** to show the boundaries of the original GBA pixels on the handheld display. The grid is off by default.

**Enable Game Boy Player** in **Core Settings** is on by default. It lets compatible games use the Game Bub's rumble motor through the Game Boy Player protocol.

## Save states

In **Core Settings**, select **State Slot** (1–4), then choose **Save State** or **Load State**. While playing, press **Y** to save to the selected slot or **X** to load from it. Exit the game normally to keep changes. The firmware writes the four slots to a `.mgstate` file next to the ROM. Cartridge saves use a separate `.mgsav` file.

## Build and test

Use Bash, Java, Python 3 and Vivado with Artix-7 support. The release was built with Vivado 2025.2. Clone with submodules, then run these commands from the repository root:

```sh
git submodule update --init --recursive
python3 -m pip install -r fpga/framework/requirements.txt
python3 fpga/scripts/build_core.py \
  --name gba-mister-gamebub_rev4 \
  --target gamebub_rev4 \
  --core-class net.gamebub.core.gba.HandheldMisterGba \
  --build-root fpga/out/gba-mister-rev4
```

Copy the resulting `gba-mister-gamebub_rev4.bit` and the three JSON files from [fpga/cores/Game-Bub.MisterGBA](fpga/cores/Game-Bub.MisterGBA) to the SD card core folder. The release implementation used the Vivado `Explore` placement directive and `AggressiveExplore` post-placement physical optimization. Check the routed timing report before using a locally built bitstream.

Run `bash fpga/sim/gba_mister/run.sh` with GHDL to exercise boot, video output, Direct Sound FIFO and stereo DMA, and save-state handling.

## Compatibility

The current target is Rev4. ROMs up to 29 MiB are supported. Physical cartridges, link cable, RTC persistence and rewind are outside the scope of this port.

## Credits and licenses

- GBA emulation comes from [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer). See the [upstream license and port notes](fpga/verilog/gba_mister/README.md).
- The handheld integration is based on [Game Bub v1.1.0-beta3](https://github.com/elipsitz/gamebub/tree/799511fff6218eb1dbf0e338f1d315771d825a65). The Game Bub FPGA sources and scripts retain their upstream [CERN-OHL-S-2.0](LICENSE-CERN-OHL-S) and [GPL-3.0](LICENSE-GPL-V3) licensing where applicable. The [framework license](fpga/framework/LICENSE) and the HDMI submodule's licenses apply to their respective components.
