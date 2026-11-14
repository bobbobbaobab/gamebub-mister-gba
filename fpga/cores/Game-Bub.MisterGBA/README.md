# Game Boy Advance (MiSTer) for Game Bub

Experimental external core for the Game Bub rev4. It uses the MiSTer GBA
VHDL core and its original savestate format inside four 512 KiB slots.

## Build and install

From the repository root, with Mill, Vivado and the dependencies in
`fpga/framework/requirements.txt` available:

```sh
python3 fpga/scripts/build_core.py \
  --name gba-mister-gamebub_rev4 \
  --target gamebub_rev4 \
  --core-class net.gamebub.core.gba.HandheldMisterGba \
  --build-root fpga/out/gba-mister-rev4
```

Copy `core.json`, `files.json`, `settings.json` and the resulting
`gba-mister-gamebub_rev4.bit` to `/cores/Game-Bub.MisterGBA/` on the SD card.
The core ships with the upstream open-source BIOS. For a BIOS override,
place your own 16 KiB `gba_bios.bin` in the same folder.

In Core Settings, select **State Slot**, then **Save State** or **Load
State**. The stock firmware writes the four slots to `<rom>.mgstate` on
normal exit. Cartridge saves use a 128 KiB `<rom>.mgsav` file. The firmware
loads both files on launch.
The MiSTer savestate engine excludes cartridge backup bytes from snapshots.

The single-chip SDRAM window reserves 3 MiB above the ROM for work RAM,
cartridge backup and snapshots. The first release therefore accepts ROM
files up to 29 MiB. The prototype uses ROM files on SD and standard video
and audio. Hardware link, physical cartridges, RTC persistence, rewind,
64 MiB ROM mapping and MiSTer's per-game overrides are outside this port.

## Simulation

Run `bash fpga/sim/gba_mister/run.sh` from the repository root with GHDL
4.x. The test uses a small synthetic BIOS and ARM ROM with modeled memory
ports. It checks ROM execution, a rendered pixel, stereo PCM with the audio
DMA channels swapped, empty-slot rejection, and save/restore in slot 3 across
a simulated core restart. The audio check observes the GBA mixer's digital
output. Handheld audio output, SDRAM pins, ESP32 SPI and SD transfers require
separate hardware testing.
