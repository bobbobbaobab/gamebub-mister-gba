library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

use work.pProc_bus_gba.all;
use work.pReg_gba_serial.all;

entity gba_serial is
   port 
   (
      clk100            : in    std_logic;  
      gb_bus            : inout proc_bus_gb_type := ((others => 'Z'), (others => 'Z'), (others => 'Z'), 'Z', 'Z', 'Z', "ZZ", "ZZZZ", 'Z');
      
      new_cycles        : in  unsigned(7 downto 0);
      new_cycles_valid  : in  std_logic;
      gbp_enable        : in  std_logic;
      gbp_sc            : in  std_logic;
      gbp_si            : in  std_logic;
      gbp_so            : out std_logic;
      
      IRP_Serial        : out std_logic := '0'
   );
end entity;

architecture arch of gba_serial is

   signal REG_SIODATA32   : std_logic_vector(SIODATA32  .upper downto SIODATA32  .lower) := (others => '0');
   signal REG_SIOMULTI2   : std_logic_vector(SIOMULTI2  .upper downto SIOMULTI2  .lower) := (others => '0');
   signal REG_SIOMULTI3   : std_logic_vector(SIOMULTI3  .upper downto SIOMULTI3  .lower) := (others => '0');
   signal REG_SIOCNT      : std_logic_vector(SIOCNT     .upper downto SIOCNT     .lower) := (others => '0');
   signal REG_SIOMLT_SEND : std_logic_vector(SIOMLT_SEND.upper downto SIOMLT_SEND.lower) := (others => '0');
   signal REG_SIODATA8    : std_logic_vector(SIODATA8   .upper downto SIODATA8   .lower) := (others => '0');
   signal REG_RCNT        : std_logic_vector(RCNT       .upper downto RCNT       .lower) := (others => '0');
   signal REG_IR          : std_logic_vector(IR         .upper downto IR         .lower) := (others => '0');
   signal REG_JOYCNT      : std_logic_vector(JOYCNT     .upper downto JOYCNT     .lower) := (others => '0');
   signal REG_JOY_RECV    : std_logic_vector(JOY_RECV   .upper downto JOY_RECV   .lower) := (others => '0');
   signal REG_JOY_TRANS   : std_logic_vector(JOY_TRANS  .upper downto JOY_TRANS  .lower) := (others => '0');
   signal REG_JOYSTAT     : std_logic_vector(JOYSTAT    .upper downto JOYSTAT    .lower) := (others => '0');

   signal SIOCNT_READBACK : std_logic_vector(SIOCNT     .upper downto SIOCNT     .lower) := (others => '0');
   signal SIOCNT_written  : std_logic;
   signal SIOCNT_byte_en  : std_logic_vector(3 downto 0);

   signal SIO_start       : std_logic := '0';
   signal cycles          : unsigned(11 downto 0) := (others => '0');
   signal bitcount        : integer range 0 to 31 := 0;
   signal gbp_mode        : std_logic;
   signal gbp_transfer    : std_logic := '0';
   signal previous_sc     : std_logic := '1';
   signal serial_out      : std_logic := '1';
   signal serial_shift    : std_logic_vector(31 downto 0) := (others => '0');
   

begin 

   -- SIODATA32 shares its two halves with SIOMULTI0 and SIOMULTI1.
   gb_bus.Dout <= REG_SIODATA32 when unsigned(gb_bus.Adr) = SIODATA32.Adr else (others => 'Z');
   gb_bus.done <= '1' when unsigned(gb_bus.Adr) = SIODATA32.Adr else 'Z';
   iSIOMULTI2   : entity work.eProcReg_gba generic map (SIOMULTI2  ) port map  (clk100, gb_bus, REG_SIOMULTI2  , REG_SIOMULTI2  );  
   iSIOMULTI3   : entity work.eProcReg_gba generic map (SIOMULTI3  ) port map  (clk100, gb_bus, REG_SIOMULTI3  , REG_SIOMULTI3  );  
   iSIOCNT      : entity work.eProcReg_gba generic map (SIOCNT     ) port map  (clk100, gb_bus, SIOCNT_READBACK, REG_SIOCNT     , SIOCNT_written, SIOCNT_byte_en);
   iSIOMLT_SEND : entity work.eProcReg_gba generic map (SIOMLT_SEND) port map  (clk100, gb_bus, REG_SIOMLT_SEND, REG_SIOMLT_SEND);  
   iSIODATA8    : entity work.eProcReg_gba generic map (SIODATA8   ) port map  (clk100, gb_bus, REG_SIODATA8   , REG_SIODATA8   );  
   iRCNT        : entity work.eProcReg_gba generic map (RCNT       ) port map  (clk100, gb_bus, REG_RCNT       , REG_RCNT       );  
   iIR          : entity work.eProcReg_gba generic map (IR         ) port map  (clk100, gb_bus, REG_IR         , REG_IR         );  
   iJOYCNT      : entity work.eProcReg_gba generic map (JOYCNT     ) port map  (clk100, gb_bus, REG_JOYCNT     , REG_JOYCNT     );  
   iJOY_RECV    : entity work.eProcReg_gba generic map (JOY_RECV   ) port map  (clk100, gb_bus, REG_JOY_RECV   , REG_JOY_RECV   );  
   iJOY_TRANS   : entity work.eProcReg_gba generic map (JOY_TRANS  ) port map  (clk100, gb_bus, REG_JOY_TRANS  , REG_JOY_TRANS  );  
   iJOYSTAT     : entity work.eProcReg_gba generic map (JOYSTAT    ) port map  (clk100, gb_bus, REG_JOYSTAT    , REG_JOYSTAT    );  
   
   -- Game Boy Player is the clock master in normal 32-bit mode.
   gbp_mode <= '1' when gbp_enable = '1' and REG_RCNT(15) = '0' and
                        REG_SIOCNT(13 downto 12) = "01" and REG_SIOCNT(0) = '0' else '0';
   gbp_so <= serial_out when gbp_mode = '1' and gbp_transfer = '1' else '1';
   SIOCNT_READBACK <= REG_SIOCNT(15 downto 8) & SIO_start & "000" &
                      REG_SIOCNT(3) & gbp_si & REG_SIOCNT(1 downto 0) when gbp_mode = '1' else
                      REG_SIOCNT(15 downto 8) & SIO_start & REG_SIOCNT(6 downto 0);
   
   process (clk100)
   begin
      if rising_edge(clk100) then
      
         IRP_Serial <= '0';
         previous_sc <= gbp_sc;

         if (unsigned(gb_bus.Adr) = SIODATA32.Adr and gb_bus.rnw = '0' and gb_bus.ena = '1') then
            for i in 0 to 3 loop
               if (gb_bus.bEna(i) = '1') then
                  REG_SIODATA32(i * 8 + 7 downto i * 8) <= gb_bus.Din(i * 8 + 7 downto i * 8);
               end if;
            end loop;
         end if;

         if (gbp_transfer = '1') then
            if (gbp_mode = '0') then
               gbp_transfer <= '0';
               SIO_start <= '0';
            elsif (previous_sc = '1' and gbp_sc = '0') then
               serial_out <= serial_shift(31);
            elsif (previous_sc = '0' and gbp_sc = '1') then
               serial_shift <= serial_shift(30 downto 0) & gbp_si;
               if (bitcount = 31) then
                  REG_SIODATA32 <= serial_shift(30 downto 0) & gbp_si;
                  gbp_transfer <= '0';
                  SIO_start <= '0';
                  IRP_Serial <= REG_SIOCNT(14);
               else
                  bitcount <= bitcount + 1;
               end if;
            end if;
         elsif (SIO_start = '1') then
            if (new_cycles_valid = '1') then
               cycles <= cycles + new_cycles;
            else
               if ((REG_SIOCNT(1) = '0' and cycles >= 64) or (REG_SIOCNT(1) = '1' and cycles >= 8)) then
                  if (REG_SIOCNT(1) = '1') then
                     cycles <= cycles - 8;
                  else
                     cycles <= cycles - 64;
                  end if;
                  
                  if ((REG_SIOCNT(12) = '0' and bitcount = 7) or (REG_SIOCNT(12) = '1' and bitcount = 31)) then
                     if (REG_SIOCNT(14) = '1') then
                        IRP_Serial <= '1';
                     end if;
                     SIO_start <= '0';
                  else
                     bitcount <= bitcount + 1;
                  end if;
               end if;
            end if;
         end if;

   
         if (SIOCNT_written = '1' and (gbp_mode = '0' or SIOCNT_byte_en(0) = '1')) then
            if (REG_SIOCNT(7) = '1') then
               if (gbp_transfer = '0') then
                  SIO_start <= '1';
                  bitcount  <= 0;
                  cycles    <= (others => '0');
                  gbp_transfer <= gbp_mode;
                  if (gbp_mode = '1') then
                     serial_shift <= REG_SIODATA32;
                     serial_out <= REG_SIOCNT(3);
                  end if;
               end if;
            elsif (gbp_transfer = '1') then
               gbp_transfer <= '0';
               SIO_start <= '0';
            end if;
         end if;

         if (gb_bus.rst = '1') then
            REG_SIODATA32 <= (others => '0');
            gbp_transfer <= '0';
            SIO_start <= '0';
            IRP_Serial <= '0';
         end if;
    
      end if;
   end process;

end architecture;





