library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity gba_gamebub_tb is
end entity;

architecture test of gba_gamebub_tb is
  subtype word is std_logic_vector(31 downto 0);
  type words is array (natural range <>) of word;
  type doublewords is array (natural range <>) of std_logic_vector(63 downto 0);

  -- ARM ROM: write EWRAM, display a pixel, then play two alternating PCM
  -- patterns. DMA1 feeds FIFO B (right) and DMA2 feeds FIFO A (left).
  constant rom : words(0 to 45) := (
    x"E3A00402", x"E59F108C", x"E5801000", x"E3A00301",
    x"E3A01003", x"E3811B01", x"E5801000", x"E59F2078",
    x"E3A0101F", x"E5821000", x"E3A02402", x"E2822C01",
    x"E59F4068", x"E59F5068", x"E3A03040", x"E4824004",
    x"E58250FC", x"E2533001", x"1AFFFFFB", x"E3A01080",
    x"E5801084", x"E59F104C", x"E5801080", x"E59F1048",
    x"E58010BC", x"E28010A4", x"E58010C0", x"E3A014B7",
    x"E58010C4", x"E59F1034", x"E58010C8", x"E28010A0",
    x"E58010CC", x"E3A014B7", x"E58010D0", x"E59F1020",
    x"E5801100", x"EAFFFFFE", x"12345678", x"060001E0",
    x"40C040C0", x"20E020E0", x"9A0C0000", x"02000200",
    x"02000100", x"0080FE00"
  );
  constant marker : word := x"12345678";
  constant slot_base : natural := 2 * 16#10000#;
  constant clock_half_period : time := 5963 ps;

  signal clk : std_logic := '0';
  signal run, pause : std_logic := '0';
  signal bios_address : std_logic_vector(11 downto 0) := (others => '0');
  signal bios_data : word := (others => '0');
  signal bios_write : std_logic := '0';
  signal rom_request, rom_done : std_logic := '0';
  signal rom_address : std_logic_vector(24 downto 0);
  signal rom_first, rom_second : word := (others => '0');
  signal work_request, work_read, work_done : std_logic := '0';
  signal work_address : std_logic_vector(25 downto 0);
  signal work_write_data, work_read_data : word := (others => '0');
  signal state_save, state_load, state_loaded, state_busy : std_logic := '0';
  signal state_request, state_read, state_done : std_logic := '0';
  signal state_address : std_logic_vector(25 downto 0);
  signal state_write_data, state_read_data : std_logic_vector(63 downto 0);
  signal pixel_write : std_logic;
  signal pixel_x, pixel_y : std_logic_vector(7 downto 0);
  signal pixel_data : std_logic_vector(17 downto 0);

  signal audio_left, audio_right : std_logic_vector(15 downto 0);
  signal left_positive, left_negative, right_positive, right_negative : boolean := false;

  signal ewram_word : word := (others => '0');
  signal state_header : word := (others => '1');
  signal clear_marker, red_pixel_seen : std_logic := '0';
begin
  clk <= not clk after clock_half_period;

  dut : entity work.gba_gamebub
    port map (
      clk => clk, run => run, pause => pause, flash_1m => '0',
      rom_words => std_logic_vector(to_unsigned(rom'length, 25)),
      keys => (others => '0'),
      bios_address => bios_address, bios_data => bios_data, bios_write => bios_write,
      rom_request => rom_request, rom_address => rom_address, rom_first => rom_first,
      rom_second => rom_second, rom_done => rom_done,
      work_request => work_request, work_read => work_read, work_address => work_address,
      work_write_data => work_write_data, work_read_data => work_read_data, work_done => work_done,
      state_save => state_save, state_load => state_load, state_slot => "10",
      state_busy => state_busy, state_loaded => state_loaded,
      state_request => state_request, state_read => state_read, state_address => state_address,
      state_write_data => state_write_data, state_read_data => state_read_data, state_done => state_done,
      pixel_write => pixel_write, pixel_x => pixel_x, pixel_y => pixel_y, pixel_data => pixel_data,
      audio_left => audio_left, audio_right => audio_right, rumble => open
    );

  memory : process (clk)
    variable ewram : words(0 to 65535) := (others => (others => '0'));
    variable snapshot : doublewords(0 to 65535) := (others => (others => '1'));
    variable addr, partner : natural;
  begin
    if rising_edge(clk) then
      left_positive <= left_positive or audio_left = x"4000";
      left_negative <= left_negative or audio_left = x"C000";
      right_positive <= right_positive or audio_right = x"2000";
      right_negative <= right_negative or audio_right = x"E000";

      rom_done <= rom_request;
      work_done <= work_request;
      state_done <= state_request;
      if rom_request = '1' then
        addr := to_integer(unsigned(rom_address));
        if addr < rom'length then
          partner := to_integer(unsigned(rom_address) xor to_unsigned(1, 25));
          rom_first <= rom(addr);
          rom_second <= rom(partner);
        else
          rom_first <= (others => '0');
          rom_second <= (others => '0');
        end if;
      end if;
      if clear_marker = '1' then
        ewram(0) := (others => '0');
        ewram_word <= ewram(0);
      end if;
      if work_request = '1' then
        addr := to_integer(unsigned(work_address)) - 16#20000#;
        if work_read = '1' then
          work_read_data <= ewram(addr);
        else
          ewram(addr) := work_write_data;
          if addr = 0 then
            ewram_word <= ewram(0);
          end if;
        end if;
      end if;
      if state_request = '1' then
        addr := to_integer(unsigned(state_address)) / 2;
        assert addr >= slot_base and addr < slot_base + snapshot'length
          report "Savestate accessed outside the selected slot" severity failure;
        addr := addr - slot_base;
        if state_read = '1' then
          state_read_data <= snapshot(addr);
        else
          snapshot(addr) := state_write_data;
          state_header <= snapshot(0)(63 downto 32);
        end if;
      end if;
      if pixel_write = '1' and pixel_x = x"00" and pixel_data(17 downto 13) = "11111"
        and pixel_data(11 downto 0) = x"000" then
        red_pixel_seen <= '1';
      end if;
    end if;
  end process;

  stimulus : process
    procedure step is
    begin
      wait until falling_edge(clk);
    end procedure;

    procedure load_slot is
    begin
      state_load <= '1';
      step;
      state_load <= '0';
      wait until state_busy = '1' for 5 us;
      assert state_busy = '1' report "Load did not start" severity failure;
    end procedure;
  begin
    step;
    bios_write <= '1';
    bios_data <= x"E51FF004";
    step;
    bios_address <= x"001";
    bios_data <= x"08000000";
    step;
    bios_write <= '0';
    wait for 100 us;
    run <= '1';
    wait until ewram_word = marker for 200 us;
    assert ewram_word = marker report "The boot ROM did not reach EWRAM" severity failure;
    report "BIOS/ROM boot and EWRAM write passed";
    wait until red_pixel_seen = '1' for 1 ms;
    assert red_pixel_seen = '1' report "The ROM did not render the red pixel" severity failure;

    report "Video output passed";
    if not (left_positive and left_negative and right_positive and right_negative) then
      wait until left_positive and left_negative and right_positive and right_negative for 2 ms;
    end if;
    assert left_positive and left_negative and right_positive and right_negative
      report "Swapped DMA channels did not deliver the expected stereo PCM samples"
      severity failure;
    report "Stereo PCM via DMA passed";
    step;
    load_slot;
    wait until state_busy = '0' for 100 us;
    assert state_busy = '0' and state_loaded = '0' and ewram_word = marker
      report "Empty slot load changed the core" severity failure;

    step;
    state_save <= '1';
    step;
    state_save <= '0';
    wait until state_busy = '1' for 5 us;
    assert state_busy = '1' report "Save did not start" severity failure;
    wait until state_busy = '0' for 30 ms;
    assert state_busy = '0' and state_header = x"00018346"
      report "Save did not commit the state header" severity failure;

    report "Empty slot rejection and snapshot commit passed";

    -- Stop and start the core, with the snapshot still in external memory.
    step;
    run <= '0';
    clear_marker <= '1';
    step;
    clear_marker <= '0';
    wait for 50 us;
    run <= '1';
    pause <= '1';
    wait for 50 us;
    assert ewram_word = x"00000000" report "Failed to clear EWRAM before load" severity failure;
    step;
    load_slot;
    wait until state_loaded = '1' for 30 ms;
    assert state_loaded = '1' and ewram_word = marker
      report "Load did not restore the EWRAM marker" severity failure;
    report "PASS: video, empty slot rejection, slot 3 save and restore";
    stop;
    wait;
  end process;
end architecture;
