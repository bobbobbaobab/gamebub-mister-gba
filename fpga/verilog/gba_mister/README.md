# MiSTer GBA source

The VHDL in `rtl/` and `mem/` comes from the supplied archive of
[MiSTer-devel/GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer).
The unmodified `gba_top.vhd` in that archive has Git blob ID
`3d2613c94119daa1a3e6333a375495ce839f0a32`. See the upstream `LICENSE`
included here. `gba_bios.vhd` is the upstream Normmatt BIOS.

The Game Bub port exposes savestate busy status, bounds the wait for a CPU
jump before saving, and clears the ROM cache while the core is stopped so
the first ROM request after startup can be accepted. It uses inferred
block RAM with two read ports and a single write port for VRAM and other
memories in place of the upstream RAM templates and adjusts port associations
and an identifier for VHDL-2008 builds.
