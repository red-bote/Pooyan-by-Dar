---------------------------------------------------------------------------------
-- Basys 3 top level for Pooyan by Red~Bote, derived from pooyan_de10_lite.vhd by
-- Dar (darfpga@aol.fr, http://darfpga.blogspot.fr); see that file for its
-- history.
---------------------------------------------------------------------------------
--
-- release rev 01 : initial Basys 3 release
--  (23/10/2026)
--
---------------------------------------------------------------------------------
-- Educational use only
-- Do not redistribute synthetized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
---------------------------------------------------------------------------------
--
-- Main features :
--  PS2 keyboard input @onboard USB HID (PS/2 emulation)
--  Joystick input     @JXADC pins 1/2/3/4/7 = right/left/down/up/fire (active low)
--  Audio pwm output   @PmodAMP2 on JA pins 1/2/4; sw15 = audio disable, sw14 = gain
--  31kHz VGA via the MiST scandoubler; sw13 = 15kHz TV (csync on hs)
--
-- Uses 1 MMCM for clk_core = 24.576MHz from 100MHz; the former 12/6/14MHz clocks are
-- clock enables (single clock domain, pooyan_single_domain.patch)
--
-- Board buttons :
--   btnC : reset game
--   btnU, btnD : Add coin
--   btnL : Start 1 player
--   btnR : Start 2 players
--
-- Board switches :
--   sw7-0 : dip switch 2
--   sw11-8: dip switch 1 Coinage A (bits 3-0), down = 1C1C; Coinage B fixed
--   sw13  : 0 = 31kHz VGA (scandoubler), 1 = 15kHz TV
--
-- Keyboard players inputs (MAME defaults) :
--
--   5 : Add coin
--   2 : Start 2 players
--   1 : Start 1 player
--   LEFT CTRL   : Fire
--   RIGHT arrow : rotate right
--   LEFT  arrow : rotate left
--   UP    arrow : rotate up
--   DOWN  arrow : rotate down
--
-- Other details : see pooyan.vhd
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity pooyan_basys3 is
port(
  clk            : in std_logic;
  btnC           : in std_logic;
  btnU           : in std_logic;
  btnD           : in std_logic;
  btnL           : in std_logic;
  btnR           : in std_logic;
  sw             : in std_logic_vector(15 downto 0);

  vga_r     : out std_logic_vector(3 downto 0);
  vga_g     : out std_logic_vector(3 downto 0);
  vga_b     : out std_logic_vector(3 downto 0);
  vga_hs    : out std_logic;
  vga_vs    : out std_logic;

  JXADC            : in  std_logic_vector(4 downto 0);
  ps2_clk          : in  std_logic;
  ps2_dat          : in  std_logic;
  O_PMODAMP2_AIN   : out std_logic;
  O_PMODAMP2_GAIN  : out std_logic;
  O_PMODAMP2_SHUTD : out std_logic
);
end pooyan_basys3;

architecture struct of pooyan_basys3 is

  signal clk_core    : std_logic;
  signal mmcm_locked : std_logic;
  signal reset_s     : std_logic_vector(1 downto 0) := "11";
  signal reset       : std_logic;

  signal ph       : std_logic_vector(1 downto 0) := "00";
  signal ce6      : std_logic;
  signal ce6n     : std_logic;
  signal ce12     : std_logic;
  signal ce12n    : std_logic;
  signal clk6_lvl : std_logic;

  constant CE14_INC : unsigned(20 downto 0) := to_unsigned(610959, 21);
  signal ce14_acc   : unsigned(20 downto 0) := (others => '0');
  signal ce14       : std_logic;

  signal r         : std_logic_vector(2 downto 0);
  signal g         : std_logic_vector(2 downto 0);
  signal b         : std_logic_vector(1 downto 0);
  signal csync     : std_logic;
  signal blankn    : std_logic;
  signal hsync     : std_logic;
  signal vsync     : std_logic;
  signal tv15Khz_mode : std_logic;

  signal scanlines : std_logic_vector(1 downto 0) := "00";
  signal video_ri  : std_logic_vector(5 downto 0);
  signal video_gi  : std_logic_vector(5 downto 0);
  signal video_bi  : std_logic_vector(5 downto 0);
  signal vga_ro    : std_logic_vector(5 downto 0);
  signal vga_go    : std_logic_vector(5 downto 0);
  signal vga_bo    : std_logic_vector(5 downto 0);
  signal vga_hs_o  : std_logic;
  signal vga_vs_o  : std_logic;

  signal audio           : std_logic_vector(10 downto 0);
  signal pwm_accumulator : std_logic_vector(12 downto 0);
  -- typed concatenations: '&' inside a type conversion is ambiguous (Synth 8-944)
  signal pwm_prev        : std_logic_vector(12 downto 0);
  signal audio_x4        : std_logic_vector(12 downto 0);

  -- 2-FF synchronizers for the asynchronous inputs
  signal ps2_clk_meta, ps2_clk_s : std_logic := '1';
  signal ps2_dat_meta, ps2_dat_s : std_logic := '1';
  signal jxadc_meta, jxadc_s     : std_logic_vector(4 downto 0) := (others => '1');
  signal btn_meta, btn_s         : std_logic_vector(3 downto 0) := (others => '0'); -- U, D, L, R
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of reset_s : signal is "TRUE";
  attribute ASYNC_REG of ps2_clk_meta, ps2_clk_s, ps2_dat_meta, ps2_dat_s : signal is "TRUE";
  attribute ASYNC_REG of jxadc_meta, jxadc_s, btn_meta, btn_s : signal is "TRUE";

  signal kbd_intr      : std_logic;
  signal kbd_scancode  : std_logic_vector(7 downto 0);
  signal kbd_rel       : std_logic := '0';
  signal kbd_joy       : std_logic_vector(7 downto 0) := (others => '0');
  signal joyPCFRLDU : std_logic_vector(7 downto 0);
  -- dip switch 1 : Coinage A (bits 3-0) on sw11-8, switch down = DE10 default,
  -- up inverts the bit; Coinage B (bits 7-4) fixed
  constant DIP1_DEFAULT : std_logic_vector(7 downto 0) := X"FF";
  signal dip1           : std_logic_vector(7 downto 0);

begin

  -- core held in reset until the MMCM locks; asserted asynchronously,
  -- released synchronously to clk_core
  process (clk_core, btnC, mmcm_locked)
  begin
    if btnC = '1' or mmcm_locked = '0' then
      reset_s <= "11";
    elsif rising_edge(clk_core) then
      reset_s <= reset_s(0) & '0';
    end if;
  end process;
  reset <= reset_s(1);

  tv15Khz_mode <= sw(13);

  -- Clock 24.576MHz (2 x 12.288MHz) for pooyan core and sound_board
  clocks : entity work.clk_wiz_0
  port map(
    clk_in1  => clk,
    clk_out1 => clk_core,
    reset    => btnC,
    locked   => mmcm_locked
  );

  -- clock enables: ph counts 4 clk_core edges per former 6MHz period (ce6/ce6n =
  -- clock_6 rising/falling, ce12/ce12n = clock_12 rising/falling, clk6_lvl = clock_6
  -- level); ce14 = 14.318MHz from a phase accumulator (610959 / 2^20 x clk_core)
  process (clk_core)
  begin
    if rising_edge(clk_core) then
      if reset = '1' then
        ph <= "00";
      else
        ph <= ph + '1';
      end if;
      ce14_acc <= ('0' & ce14_acc(19 downto 0)) + CE14_INC;
    end if;
  end process;

  ce6      <= '1' when ph = "11" else '0';
  ce6n     <= '1' when ph = "01" else '0';
  ce12     <= ph(0);
  ce12n    <= not ph(0);
  clk6_lvl <= not ph(1);
  ce14     <= ce14_acc(20);

  -- synchronize asynchronous inputs to the core clock
  process(clk_core)
  begin
    if rising_edge(clk_core) then
      ps2_clk_meta <= ps2_clk;      ps2_clk_s <= ps2_clk_meta;
      ps2_dat_meta <= ps2_dat;      ps2_dat_s <= ps2_dat_meta;
      jxadc_meta   <= JXADC;        jxadc_s   <= jxadc_meta;
      btn_meta     <= btnU & btnD & btnL & btnR;
      btn_s        <= btn_meta;
    end if;
  end process;

  -- Pooyan
  pooyan : entity work.pooyan
  port map(
    clk_core   => clk_core,
    ce6        => ce6,
    ce6n       => ce6n,
    ce12       => ce12,
    ce12n      => ce12n,
    clk6_lvl   => clk6_lvl,
    ce14       => ce14,
    reset      => reset,

  -- tv15Khz_mode => tv15Khz_mode,
    video_r      => r,
    video_g      => g,
    video_b      => b,
    video_csync  => csync,
    video_blankn => blankn,
    video_hs     => hsync,
    video_vs     => vsync,
    audio_out    => audio,

    dip_switch_1 => dip1,  -- Coinage_B / Coinage_A
    dip_switch_2 => sw(7 downto 0), -- Sound(8)/Difficulty(7-5)/Bonus(4)/Cocktail(3)/lives(2-1)

    start2      => joyPCFRLDU(7),
    start1      => joyPCFRLDU(6),
    coin1       => joyPCFRLDU(5),

    fire1       => joyPCFRLDU(4),
    right1      => joyPCFRLDU(3),
    left1       => joyPCFRLDU(2),
    down1       => joyPCFRLDU(1),
    up1         => joyPCFRLDU(0),

    fire2       => joyPCFRLDU(4),
    right2      => joyPCFRLDU(3),
    left2       => joyPCFRLDU(2),
    down2       => joyPCFRLDU(1),
    up2         => joyPCFRLDU(0),

    dbg_cpu_addr => open
  );

  -- adapt video to 6bits/color for the scandoubler, black during blank
  video_ri <= r&"000"  when blankn = '1' else "000000";
  video_gi <= g&"000"  when blankn = '1' else "000000";
  video_bi <= b&"0000" when blankn = '1' else "000000";

  -- 31kHz VGA : MiST scandoubler
  scandoubler : entity work.scandoubler
  port map (
    clk_sys   => clk_core,
    scanlines => scanlines,
    ce_x1     => ce6,  -- 6.144MHz pixel enable
    ce_x2     => ce12, -- 2 x ce_x1
    hs_in     => hsync,
    vs_in     => vsync,
    r_in      => video_ri,
    g_in      => video_gi,
    b_in      => video_bi,
    hs_out    => vga_hs_o,
    vs_out    => vga_vs_o,
    r_out     => vga_ro,
    g_out     => vga_go,
    b_out     => vga_bo
  );

  -- adapt video to 4bits/color only
  vga_r <= video_ri(5 downto 2) when tv15Khz_mode = '1' else vga_ro(5 downto 2);
  vga_g <= video_gi(5 downto 2) when tv15Khz_mode = '1' else vga_go(5 downto 2);
  vga_b <= video_bi(5 downto 2) when tv15Khz_mode = '1' else vga_bo(5 downto 2);

  -- synchro composite/ synchro horizontale
  vga_hs <= csync when tv15Khz_mode = '1' else vga_hs_o;
  -- commutation rapide / synchro verticale
  vga_vs <= '1'   when tv15Khz_mode = '1' else vga_vs_o;

  -- get scancode from keyboard
  keyboard : entity work.io_ps2_keyboard
  port map (
    clk       => clk_core, -- synchrounous clock with core
    kbd_clk   => ps2_clk_s,
    kbd_dat   => ps2_dat_s,
    interrupt => kbd_intr,
    scancode  => kbd_scancode
  );

  -- translate scancode to joystick (MAME default keys, PS/2 set 2 codes)
  -- F0 marks a release; E0 is ignored, as in kbd_joystick (keypad 8/2/4/6
  -- also act as arrows, Right Ctrl as Left Ctrl).
  process(clk_core)
  begin
    if rising_edge(clk_core) then
      if kbd_intr = '1' then
        if kbd_scancode = x"F0" then
          kbd_rel <= '1';
        elsif kbd_scancode /= x"E0" then
          kbd_rel <= '0';
          if kbd_scancode = x"75" then kbd_joy(0) <= not kbd_rel; end if; -- up arrow
          if kbd_scancode = x"72" then kbd_joy(1) <= not kbd_rel; end if; -- down arrow
          if kbd_scancode = x"6B" then kbd_joy(2) <= not kbd_rel; end if; -- left arrow
          if kbd_scancode = x"74" then kbd_joy(3) <= not kbd_rel; end if; -- right arrow
          if kbd_scancode = x"14" then kbd_joy(4) <= not kbd_rel; end if; -- left ctrl : fire
          if kbd_scancode = x"2E" then kbd_joy(5) <= not kbd_rel; end if; -- 5 : coin
          if kbd_scancode = x"16" then kbd_joy(6) <= not kbd_rel; end if; -- 1 : start 1
          if kbd_scancode = x"1E" then kbd_joy(7) <= not kbd_rel; end if; -- 2 : start 2
        end if;
      end if;
    end if;
  end process;

  -- merge keyboard, JXADC joystick (active low) and buttons; player 2 mirrors
  -- player 1 as on the DE10-lite top
  dip1 <= DIP1_DEFAULT xor (X"0" & sw(11 downto 8));

  joyPCFRLDU(0) <= kbd_joy(0) or not jxadc_s(3);           -- up    (JXADC4)
  joyPCFRLDU(1) <= kbd_joy(1) or not jxadc_s(2);           -- down  (JXADC3)
  joyPCFRLDU(2) <= kbd_joy(2) or not jxadc_s(1);           -- left  (JXADC2)
  joyPCFRLDU(3) <= kbd_joy(3) or not jxadc_s(0);           -- right (JXADC1)
  joyPCFRLDU(4) <= kbd_joy(4) or not jxadc_s(4);           -- fire  (JXADC7)
  joyPCFRLDU(5) <= kbd_joy(5) or btn_s(3) or btn_s(2);  -- coin (btnU, btnD)
  joyPCFRLDU(6) <= kbd_joy(6) or btn_s(1);              -- start 1 (btnL)
  joyPCFRLDU(7) <= kbd_joy(7) or btn_s(0);              -- start 2 (btnR)

  -- pwm sound output

  pwm_prev <= '0' & pwm_accumulator(11 downto 0);
  audio_x4 <= audio & "00";

  process(clk_core)  -- same rate as pooyan_sound_board (ce14)
  begin
    if rising_edge(clk_core) and ce14 = '1' then
      pwm_accumulator  <=  std_logic_vector(unsigned(pwm_prev) + unsigned(audio_x4));
    end if;
  end process;

  O_PMODAMP2_AIN   <= pwm_accumulator(12);
  O_PMODAMP2_SHUTD <= not sw(15); -- sw15 up = amp shut down (audio disabled)
  O_PMODAMP2_GAIN  <= not sw(14); -- sw14 up = gain active (GAIN active low)

end struct;
