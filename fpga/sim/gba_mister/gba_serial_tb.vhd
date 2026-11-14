library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pProc_bus_gba.all;

entity gba_serial_tb is
end entity;

architecture test of gba_serial_tb is
  signal clk : std_logic := '0';
  signal bus_io : proc_bus_gb_type;
  signal player, irq : std_logic := '0';
  signal sc, si, so : std_logic := '1';
  signal new_cycles_valid : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.gba_serial
    port map (
      clk100 => clk, gb_bus => bus_io,
      new_cycles => to_unsigned(8, 8), new_cycles_valid => new_cycles_valid,
      gbp_enable => player, gbp_sc => sc, gbp_si => si, gbp_so => so,
      IRP_Serial => irq
    );

  process
    procedure step is
    begin
      wait until rising_edge(clk);
      wait until falling_edge(clk);
    end procedure;

    procedure write_register(
      address : natural; data : std_logic_vector(31 downto 0);
      bytes : std_logic_vector(3 downto 0) := "1111"
    ) is
    begin
      bus_io.Adr <= std_logic_vector(to_unsigned(address, bus_io.Adr'length));
      bus_io.Din <= data;
      bus_io.bEna <= bytes;
      bus_io.rnw <= '0';
      bus_io.ena <= '1';
      step;
      bus_io.ena <= '0';
      bus_io.rnw <= '1';
      step;
    end procedure;

    constant outgoing : std_logic_vector(31 downto 0) := x"494EBEEF";
    constant incoming : std_logic_vector(31 downto 0) := x"10000010";
  begin
    bus_io.ena <= '0';
    bus_io.rst <= '1';
    bus_io.Adr <= (others => '0');
    bus_io.rnw <= '1';
    bus_io.bEna <= (others => '0');
    step;
    bus_io.rst <= '0';
    player <= '1';
    write_register(16#120#, x"494E0000", "1100");
    write_register(16#120#, x"0000BEEF", "0011");
    assert bus_io.Dout = outgoing report "SIODATA32 byte lanes failed" severity failure;
    write_register(16#128#, x"00005080", "0011");
    assert bus_io.Dout(7) = '1' report "External transfer failed to arm" severity failure;
    write_register(16#128#, x"00005000", "0010");
    assert bus_io.Dout(7) = '1' report "High-byte write changed start status" severity failure;

    for i in 31 downto 0 loop
      sc <= '0';
      si <= incoming(i);
      step;
      assert so = outgoing(i) report "Wrong outgoing serial bit" severity failure;
      sc <= '1';
      step;
      if i > 0 then
        assert irq = '0' and bus_io.Dout(7) = '1'
          report "External transfer finished early" severity failure;
      end if;
    end loop;
    assert irq = '1' and bus_io.Dout(7) = '0'
      report "External transfer did not clear busy and raise IRQ" severity failure;
    bus_io.Adr <= std_logic_vector(to_unsigned(16#120#, bus_io.Adr'length));
    step;
    assert bus_io.Dout = incoming and irq = '0'
      report "Received word or IRQ pulse was incorrect" severity failure;

    write_register(16#128#, x"00005080", "0011");
    player <= '0';
    step;
    assert bus_io.Dout(7) = '0' and irq = '0'
      report "Disabling Game Boy Player did not cancel its transfer" severity failure;

    -- The original internally timed serial path still finishes without GBP.
    write_register(16#128#, x"00004083", "0011");
    for i in 1 to 8 loop
      new_cycles_valid <= '1';
      step;
      new_cycles_valid <= '0';
      step;
    end loop;
    assert irq = '1' and bus_io.Dout(7) = '0'
      report "Original internally timed transfer failed" severity failure;
    report "Game Boy Player serial exchange, IRQ, cancellation and original serial path passed";
    stop;
    wait;
  end process;
end architecture;
