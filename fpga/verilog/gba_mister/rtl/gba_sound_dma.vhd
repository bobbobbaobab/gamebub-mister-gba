library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pRegmap_gba.all;
use work.pProc_bus_gba.all;
use work.pReg_gba_sound.all;

use work.pReg_savestates.all;

entity gba_sound_dma is
   generic
   (
      REG_FIFO                : regmap_type;
      REG_SAVESTATE_DMASOUND  : regmap_type
   );
   port
   (
      clk100              : in    std_logic;
      reset               : in    std_logic;

      loading_savestate   : in    std_logic;
      savestate_bus       : inout proc_bus_gb_type;

      gb_bus              : inout proc_bus_gb_type := ((others => 'Z'), (others => 'Z'), (others => 'Z'), 'Z', 'Z', 'Z', "ZZ", "ZZZZ", 'Z');

      settings_new        : in    std_logic;
      Enable_RIGHT        : in    std_logic;
      Enable_LEFT         : in    std_logic;
      Timer_Select        : in    std_logic;
      Reset_FIFO          : in    std_logic;
      volume_high         : in    std_logic;

      timer0_tick         : in    std_logic;
      timer1_tick         : in    std_logic;
      dma_req             : out   std_logic := '0';

      sound_out_left      : out   signed(15 downto 0) := (others => '0');
      sound_out_right     : out   signed(15 downto 0) := (others => '0');
      sound_on            : out   std_logic := '0';

      new_sample_out      : out   std_logic;

      debug_fifocount     : out   integer
   );
end entity;

architecture arch of gba_sound_dma is
   type fifo_memory is array (0 to 7) of std_logic_vector(31 downto 0);
   signal fifo : fifo_memory := (others => (others => '0'));
   signal read_word, write_word : unsigned(2 downto 0) := (others => '0');
   signal read_byte : integer range 0 to 3 := 0;
   signal word_count : integer range 0 to 7 := 0;

   signal fifo_write_data : std_logic_vector(31 downto 0);
   signal fifo_written : std_logic;
   signal fifo_write_mask : std_logic_vector(3 downto 0);
   signal any_on, sample_tick : std_logic;
   signal sound_raw : signed(7 downto 0) := (others => '0');
   signal sound_out : signed(15 downto 0);

   signal SAVESTATE_DMASOUND : std_logic_vector(4 downto 0);
   signal SAVESTATE_DMASOUND_back : std_logic_vector(4 downto 0);
begin
   iFIFO_REGISTER : entity work.eProcReg_gba
   generic map (REG_FIFO)
   port map (clk100, gb_bus, x"00000000", fifo_write_data, fifo_written, fifo_write_mask);

   iSAVESTATE_DMASOUND : entity work.eProcReg_gba
   generic map (REG_SAVESTATE_DMASOUND)
   port map (clk100, savestate_bus, SAVESTATE_DMASOUND_back, SAVESTATE_DMASOUND);

   -- Preserve the existing snapshot fields. FIFO contents are initialized to
   -- silence on restore because the snapshot stores only count and position.
   SAVESTATE_DMASOUND_back(2 downto 0) <= std_logic_vector(to_unsigned(word_count, 3));
   SAVESTATE_DMASOUND_back(4 downto 3) <= std_logic_vector(to_unsigned(read_byte, 2));

   any_on <= Enable_LEFT or Enable_RIGHT;
   sound_on <= any_on;
   sample_tick <= any_on and ((timer0_tick and not Timer_Select) or (timer1_tick and Timer_Select));
   debug_fifocount <= word_count;
   sound_out <= shift_left(resize(sound_raw, 16), 2) when volume_high = '1' else
                shift_left(resize(sound_raw, 16), 1);
   sound_out_left  <= sound_out when Enable_LEFT  = '1' else (others => '0');
   sound_out_right <= sound_out when Enable_RIGHT = '1' else (others => '0');

   process (clk100)
      variable next_count : integer range 0 to 7;
      variable front_word : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk100) then
         dma_req <= '0';
         new_sample_out <= '0';

         if reset = '1' then
            fifo <= (others => (others => '0'));
            read_word <= (others => '0');
            write_word <= unsigned(SAVESTATE_DMASOUND(2 downto 0));
            read_byte <= to_integer(unsigned(SAVESTATE_DMASOUND(4 downto 3)));
            word_count <= to_integer(unsigned(SAVESTATE_DMASOUND(2 downto 0)));
            sound_raw <= (others => '0');
         elsif loading_savestate = '0' then
            if settings_new = '1' and Reset_FIFO = '1' then
               fifo <= (others => (others => '0'));
               read_word <= (others => '0');
               write_word <= (others => '0');
               read_byte <= 0;
               word_count <= 0;
               sound_raw <= (others => '0');
            else
               next_count := word_count;

               -- A timer overflow has its own read path, including while DMA
               -- writes the following word. On underrun, hold the last sample.
               if sample_tick = '1' and word_count > 0 then
                  front_word := fifo(to_integer(read_word));
                  sound_raw <= signed(front_word(8 * read_byte + 7 downto 8 * read_byte));
                  new_sample_out <= '1';
                  if read_byte = 3 then
                     read_word <= read_word + 1;
                     read_byte <= 0;
                     next_count := next_count - 1;
                  else
                     read_byte <= read_byte + 1;
                  end if;
               end if;

               if fifo_written = '1' and next_count < 7 then
                  for i in 0 to 3 loop
                     if fifo_write_mask(i) = '1' then
                        fifo(to_integer(write_word))(8 * i + 7 downto 8 * i) <=
                           fifo_write_data(8 * i + 7 downto 8 * i);
                     end if;
                  end loop;
                  write_word <= write_word + 1;
                  next_count := next_count + 1;
               end if;

               -- Leave room for all four words of the next DMA burst.
               if sample_tick = '1' and next_count <= 3 then
                  dma_req <= '1';
               end if;
               word_count <= next_count;
            end if;
         end if;
      end if;
   end process;
end architecture;
