library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;


entity SyncRamDualByteEnable is
   generic
   (
      is_simu     : std_logic;
      is_cyclone5 : std_logic := '0';
      BYTE_WIDTH  : natural := 8;
      ADDR_WIDTH  : natural := 6;
      BYTES       : natural := 4
   );
   port
   (
      clk        : in std_logic;

      addr_a     : in natural range 0 to 2**ADDR_WIDTH - 1;
      datain_a0  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a1  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a2  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a3  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      dataout_a  : out std_logic_vector((BYTES*BYTE_WIDTH-1) downto 0);
      we_a       : in std_logic := '1';
      be_a       : in  std_logic_vector (BYTES - 1 downto 0);

      addr_b     : in natural range 0 to 2**ADDR_WIDTH - 1;
      datain_b0  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b1  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b2  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b3  : in std_logic_vector((BYTE_WIDTH-1) downto 0);
      dataout_b  : out std_logic_vector((BYTES*BYTE_WIDTH-1) downto 0);
      we_b       : in std_logic := '1';
      be_b       : in  std_logic_vector (BYTES - 1 downto 0)
   );
end;

-- Same-clock RAM with read-first byte writes on port A.
architecture rtl of SyncRamDualByteEnable is
   type word_t is array (0 to BYTES - 1) of std_logic_vector(BYTE_WIDTH - 1 downto 0);
   type ram_t is array (0 to 2**ADDR_WIDTH - 1) of std_logic_vector(BYTE_WIDTH - 1 downto 0);
   signal data_a : word_t;
begin
   assert BYTES = 4 severity failure;
   data_a <= (datain_a0, datain_a1, datain_a2, datain_a3);

   lanes : for byte in 0 to BYTES - 1 generate
      signal ram : ram_t := (others => (others => '0'));
   begin
      process (clk)
      begin
         if rising_edge(clk) then
            if we_a = '1' and be_a(byte) = '1' then
               ram(addr_a) <= data_a(byte);
            end if;
            dataout_a((byte + 1)*BYTE_WIDTH - 1 downto byte*BYTE_WIDTH) <= ram(addr_a);
            dataout_b((byte + 1)*BYTE_WIDTH - 1 downto byte*BYTE_WIDTH) <= ram(addr_b);
         end if;
      end process;
   end generate;
end architecture;
