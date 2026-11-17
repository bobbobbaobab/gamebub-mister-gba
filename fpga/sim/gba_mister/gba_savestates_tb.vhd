library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.pProc_bus_gba.all;

entity gba_savestates_tb is
end entity;

architecture test of gba_savestates_tb is
  signal clk : std_logic := '0';
  signal save, load, busy, loaded : std_logic := '0';
  signal io_write, state_request, state_done : std_logic := '0';
  signal gb_bus : proc_bus_gb_type;
begin
  clk <= not clk after 6 ns;
  gb_bus <= (x"00000200", (others => 'Z'), x"4000088", '0', io_write,
             'Z', ACCESS_32BIT, "1111", '0');

  dut : entity work.gba_savestates
    generic map (
      Softmap_GBA_WRam_ADDR => 16#20000#,
      Softmap_GBA_FLASH_ADDR => 0, Softmap_GBA_EEPROM_ADDR => 0
    )
    port map (
      clk100 => clk, gb_on => '1', reset => open,
      load_done => loaded, increaseSSHeaderCount => '1',
      save => save, load => load, savestate_address => 0,
      savestate_busy => busy, cpu_jump => '0', bus_ena_in => '0',
      gb_bus => gb_bus, SAVE_BusAddr => open, SAVE_BusRnW => open,
      SAVE_BusACC => open, SAVE_BusWriteData => open, SAVE_Bus_ena => open,
      SAVE_BusReadData => (others => '0'), SAVE_BusReadDone => '0',
      bus_out_Din => open, bus_out_Dout => (others => '1'),
      bus_out_Adr => open, bus_out_rnw => open, bus_out_ena => state_request,
      bus_out_active => open, bus_out_be => open, bus_out_done => state_done
    );

  process (clk)
  begin
    if rising_edge(clk) then
      state_done <= state_request;
    end if;
  end process;

  stimulus : process
  begin
    wait until busy = '0' for 1 us;
    assert busy = '0' report "Savestate engine did not finish reset" severity failure;

    wait until falling_edge(clk);
    load <= '1';
    io_write <= '1';
    wait until falling_edge(clk);
    load <= '0';
    io_write <= '0';
    assert busy = '1' report "I/O write dropped the load request" severity failure;
    wait until busy = '0' for 5 us;
    assert busy = '0' and loaded = '0'
      report "Empty slot did not return to idle" severity failure;

    wait until falling_edge(clk);
    save <= '1';
    io_write <= '1';
    wait until falling_edge(clk);
    save <= '0';
    io_write <= '0';
    assert busy = '1' report "I/O write dropped the save request" severity failure;
    report "PASS: simultaneous I/O writes and savestate requests";
    stop;
    wait;
  end process;
end architecture;
