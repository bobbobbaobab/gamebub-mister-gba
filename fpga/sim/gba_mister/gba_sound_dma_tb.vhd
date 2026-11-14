library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;
use work.pReg_gba_sound.all;
use work.pReg_savestates.all;

entity gba_sound_dma_tb is
end entity;

architecture test of gba_sound_dma_tb is
  signal clk : std_logic := '0';
  signal reset, settings_new, clear_fifo, timer0, timer1 : std_logic := '0';
  signal left_enable, right_enable, timer_select : std_logic := '0';
  signal bus_mmio, bus_state : proc_bus_gb_type :=
    ((others => 'Z'), (others => 'Z'), (others => 'Z'), 'Z', 'Z', 'Z', "ZZ", "ZZZZ", 'Z');
  signal left, right : signed(15 downto 0);
  signal refill : std_logic;
begin
  clk <= not clk after 10 ns;

  dut : entity work.gba_sound_dma
    generic map (REG_FIFO => FIFO_A, REG_SAVESTATE_DMASOUND => REG_SAVESTATE_DMASOUNDA)
    port map (
      clk100 => clk, reset => reset,
      loading_savestate => '0', savestate_bus => bus_state, gb_bus => bus_mmio,
      settings_new => settings_new, Enable_LEFT => left_enable, Enable_RIGHT => right_enable,
      Timer_Select => timer_select, Reset_FIFO => clear_fifo, volume_high => '1',
      timer0_tick => timer0, timer1_tick => timer1,
      dma_req => refill, sound_out_left => left, sound_out_right => right,
      sound_on => open, new_sample_out => open, debug_fifocount => open
    );

  process
    type samples is array (positive range <>) of integer;
    constant expected : samples := (1, 3, -126, 4, 5, 6, 7, 8, 9, 10, 11, 12);

    procedure step is
    begin
      wait until falling_edge(clk);
    end procedure;

    procedure write_fifo(data : std_logic_vector(31 downto 0)) is
    begin
      bus_mmio.adr <= std_logic_vector(to_unsigned(FIFO_A.adr, proc_busadr));
      bus_mmio.din <= data;
      bus_mmio.rnw <= '0';
      bus_mmio.bEna <= "1111";
      bus_mmio.ena <= '1';
      step;
      bus_mmio.ena <= '0';
    end procedure;

    procedure check_sample(sample : integer) is
    begin
      assert left = to_signed(sample * 4, 16)
        report "FIFO expected sample " & integer'image(sample) &
               ", got " & integer'image(to_integer(left) / 4)
        severity failure;
      assert right = to_signed(0, 16) report "FIFO leaked into the right channel" severity failure;
    end procedure;
  begin
    bus_state.rst <= '1';
    step;
    bus_state.rst <= '0';
    reset <= '1';
    step;
    reset <= '0';
    left_enable <= '1';
    for i in 1 to 8 loop
      step;
    end loop;

    write_fifo(x"04820301");
    write_fifo(x"08070605");
    step;
    -- Consecutive overflows while a third word is being written.
    timer0 <= '1';
    write_fifo(x"0C0B0A09");
    check_sample(expected(1));
    step;
    check_sample(expected(2));
    for i in 3 to expected'length loop
      step;
      check_sample(expected(i));
    end loop;
    timer0 <= '0';

    timer0 <= '1';
    step;
    timer0 <= '0';
    assert refill = '1' report "An empty FIFO did not request a refill" severity failure;
    check_sample(12);

    settings_new <= '1';
    clear_fifo <= '1';
    step;
    settings_new <= '0';
    clear_fifo <= '0';
    check_sample(0);

    timer_select <= '1';
    write_fifo(x"04820301");
    step;
    timer0 <= '1';
    step;
    timer0 <= '0';
    check_sample(0);
    timer1 <= '1';
    step;
    check_sample(1);
    step;
    check_sample(3);
    step;
    check_sample(-126);
    step;
    check_sample(4);
    timer1 <= '0';

    report "Direct Sound FIFO tick, write, underrun, reset and stereo routing passed";
    stop;
    wait;
  end process;
end architecture;
