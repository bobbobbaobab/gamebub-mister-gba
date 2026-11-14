library ieee;
use ieee.std_logic_1164.all;

entity SyncRamDual is
   generic 
   (
      DATA_WIDTH : natural := 8;
      ADDR_WIDTH : natural := 6;
      WRITE_PORT_B : boolean := false
   );
   port 
   (
      clk        : in std_logic;
      
      addr_a     : in natural range 0 to 2**ADDR_WIDTH - 1;
      datain_a   : in std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_a  : out std_logic_vector((DATA_WIDTH -1) downto 0);
      we_a       : in std_logic := '1';
      re_a       : in std_logic := '1';
                 
      addr_b     : in natural range 0 to 2**ADDR_WIDTH - 1;
      datain_b   : in std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_b  : out std_logic_vector((DATA_WIDTH -1) downto 0);
      we_b       : in std_logic := '1';
      re_b       : in std_logic := '1'
   );
end;

architecture rtl of SyncRamDual is

   -- Build a 2-D array type for the RAM
   subtype word_t is std_logic_vector((DATA_WIDTH-1) downto 0);
   type memory_t is array(0 to 2**ADDR_WIDTH-1) of word_t;

   -- Declare the RAM 
   signal write_addr : natural range 0 to 2**ADDR_WIDTH - 1;
   signal write_data : word_t;
   signal write_enable : std_logic;
   signal ram : memory_t := (others => (others => '0'));

begin
   write_addr <= addr_b when WRITE_PORT_B else addr_a;
   write_data <= datain_b when WRITE_PORT_B else datain_a;
   write_enable <= we_b when WRITE_PORT_B else we_a;

   process (clk)
   begin
      if rising_edge(clk) then
         if write_enable = '1' then
            ram(write_addr) <= write_data;
         end if;
         if re_a = '1' then
            dataout_a <= ram(addr_a);
         end if;
         if re_b = '1' then
            dataout_b <= ram(addr_b);
         end if;
      end if;
   end process;
end architecture;
