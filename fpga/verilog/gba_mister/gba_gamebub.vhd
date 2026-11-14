library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gba_gamebub is
  generic (SPEEDDIV : positive := 5);
  port (
    clk, run, pause : in std_logic;
    flash_1m : in std_logic;
    rom_words : in std_logic_vector(24 downto 0);
    keys : in std_logic_vector(9 downto 0);
    gbp_enable : in std_logic := '0';
    gbp_sc, gbp_si : in std_logic := '1';
    gbp_so : out std_logic;
    bios_address : in std_logic_vector(11 downto 0);
    bios_data : in std_logic_vector(31 downto 0);
    bios_write : in std_logic;
    rom_request : out std_logic;
    rom_address : out std_logic_vector(24 downto 0);
    rom_first, rom_second : in std_logic_vector(31 downto 0);
    rom_done : in std_logic;
    work_request, work_read : out std_logic;
    work_address : out std_logic_vector(25 downto 0);
    work_write_data : out std_logic_vector(31 downto 0);
    work_read_data : in std_logic_vector(31 downto 0);
    work_done : in std_logic;
    state_save, state_load : in std_logic;
    state_slot : in std_logic_vector(1 downto 0);
    state_busy, state_loaded : out std_logic;
    state_request, state_read : out std_logic;
    state_address : out std_logic_vector(25 downto 0);
    state_write_data : out std_logic_vector(63 downto 0);
    state_read_data : in std_logic_vector(63 downto 0);
    state_done : in std_logic;
    pixel_write : out std_logic;
    pixel_x, pixel_y : out std_logic_vector(7 downto 0);
    pixel_data : out std_logic_vector(17 downto 0);
    audio_left, audio_right : out std_logic_vector(15 downto 0);
    rumble : out std_logic
  );
end entity;

architecture rtl of gba_gamebub is
  signal x : integer range 0 to 239;
  signal y : integer range 0 to 159;
  signal cycle_limit : std_logic_vector(15 downto 0);
begin
  pixel_x <= std_logic_vector(to_unsigned(x, pixel_x'length));
  pixel_y <= std_logic_vector(to_unsigned(y, pixel_y'length));
  cycle_limit <= x"0000" when pause = '1' else x"0064";

  core : entity work.gba_top
    generic map (
      -- The ROM, work memory and snapshot ports have separate base addresses.
      -- Work port: one dword per cartridge byte, then 256 KiB of EWRAM.
      Softmap_GBA_Gamerom_ADDR => 0,
      Softmap_GBA_WRam_ADDR => 16#20000#,
      Softmap_GBA_FLASH_ADDR => 0,
      Softmap_GBA_EEPROM_ADDR => 0,
      Softmap_SaveState_ADDR => 0,
      Softmap_Rewind_ADDR => 0,
      turbosound => '0',
      SPEEDDIV => SPEEDDIV
    )
    port map (
      clk100 => clk,
      GBA_on => run,
      GBA_lockspeed => '1',
      GBA_cputurbo => '0',
      GBA_flash_1m => flash_1m,
      CyclePrecalc => cycle_limit,
      Underclock => "00",
      MaxPakAddr => rom_words,
      CyclesMissing => open,
      CyclesVsyncSpeed => open,
      SramFlashEnable => '1',
      memory_remap => '0',
      matrix_mapper => '0',
      increaseSSHeaderCount => '1',
      save_state => state_save,
      load_state => state_load,
      interframe_blend => "00",
      maxpixels => '0',
      shade_mode => "000",
      hdmode2x_bg => '0',
      hdmode2x_obj => '0',
      specialmodule => '1',
      solar_in => "111",
      tilt => '0',
      rewind_on => '0',
      rewind_active => '0',
      savestate_number => to_integer(unsigned(state_slot)),
      RTC_timestampNew => '0',
      RTC_timestampIn => (others => '0'),
      RTC_timestampSaved => (others => '0'),
      RTC_savedtimeIn => (others => '0'),
      RTC_saveLoaded => '0',
      RTC_timestampOut => open,
      RTC_savedtimeOut => open,
      RTC_inuse => open,
      cheat_clear => '0',
      cheats_enabled => '0',
      cheat_on => '0',
      cheat_in => (others => '0'),
      cheats_active => open,
      sdram_read_ena => rom_request,
      sdram_read_done => rom_done,
      sdram_read_addr => rom_address,
      sdram_read_data => rom_first,
      sdram_second_dword => rom_second,
      bus_out_Din => work_write_data,
      bus_out_Dout => work_read_data,
      bus_out_Adr => work_address,
      bus_out_rnw => work_read,
      bus_out_ena => work_request,
      bus_out_done => work_done,
      SAVE_out_Din => state_write_data,
      SAVE_out_Dout => state_read_data,
      SAVE_out_Adr => state_address,
      SAVE_out_rnw => state_read,
      SAVE_out_ena => state_request,
      SAVE_out_active => open,
      SAVE_out_be => open,
      SAVE_out_done => state_done,
      bios_wraddr => bios_address,
      bios_wrdata => bios_data,
      bios_wr => bios_write,
      save_eeprom => open,
      save_sram => open,
      save_flash => open,
      state_busy => state_busy,
      load_done => state_loaded,
      KeyA => keys(0),
      KeyB => keys(1),
      KeySelect => keys(2),
      KeyStart => keys(3),
      KeyRight => keys(4),
      KeyLeft => keys(5),
      KeyUp => keys(6),
      KeyDown => keys(7),
      KeyR => keys(8),
      KeyL => keys(9),
      gbp_enable => gbp_enable,
      gbp_sc => gbp_sc,
      gbp_si => gbp_si,
      gbp_so => gbp_so,
      AnalogTiltX => (others => '0'),
      AnalogTiltY => (others => '0'),
      Rumble => rumble,
      GBA_BusAddr => (others => '0'),
      GBA_BusRnW => '0',
      GBA_BusACC => "00",
      GBA_BusWriteData => (others => '0'),
      GBA_BusReadData => open,
      GBA_Bus_written => '0',
      pixel_out_x => x,
      pixel_out_y => y,
      pixel_out_addr => open,
      pixel_out_data => pixel_data,
      pixel_out_we => pixel_write,
      largeimg_out_base => open,
      largeimg_out_addr => open,
      largeimg_out_data => open,
      largeimg_out_req => open,
      largeimg_out_done => '0',
      largeimg_newframe => '0',
      largeimg_singlebuf => '0',
      sound_out_left => audio_left,
      sound_out_right => audio_right,
      debug_cpu_pc => open,
      debug_cpu_mixed => open,
      debug_irq => open,
      debug_dma => open,
      debug_mem => open
    );
end architecture;
