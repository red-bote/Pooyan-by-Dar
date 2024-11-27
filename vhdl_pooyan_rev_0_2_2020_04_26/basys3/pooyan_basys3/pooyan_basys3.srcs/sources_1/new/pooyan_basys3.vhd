----------------------------------------------------------------------------------
-- Company: Red~Bote 
-- Engineer: Glenn Neidermeier
-- 
-- Create Date: 11/26/2024 09:23:13 PM
-- Design Name: 
-- Module Name: rtl_top - struct
-- Project Name: 
-- Target Devices: Basys 3 board with Xilinx Artix-7
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
--  vga_scandoubler.v from https://github.com/DECAfpga/Arcade_Pooyan/blob/main/deca/vga_scandoubler.v
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--  based on vhdl_pooyan_rev_0_2_2020_04_26/rtl_dar/pooyan_de10_lite.vhd
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity pooyan_basys3 is
    port (
        clk : in std_logic;
        sw : in std_logic_vector (15 downto 0);

        O_PMODAMP2_AIN : out std_logic;
        O_PMODAMP2_GAIN : out std_logic;
        O_PMODAMP2_SHUTD : out std_logic;

        vga_r : out std_logic_vector (3 downto 0);
        vga_g : out std_logic_vector (3 downto 0);
        vga_b : out std_logic_vector (3 downto 0);
        vga_hs : out std_logic;
        vga_vs : out std_logic;

        ps2_clk : in std_logic;
        ps2_dat : in std_logic
    );
end pooyan_basys3;

architecture struct of pooyan_basys3 is

    signal clock_12 : std_logic;
    signal clock_14 : std_logic;
    signal reset : std_logic;
    signal clock_6 : std_logic;

    signal r : std_logic_vector(2 downto 0);
    signal g : std_logic_vector(2 downto 0);
    signal b : std_logic_vector(1 downto 0);
    signal csync : std_logic;
    signal blankn : std_logic;
    signal hsync : std_logic;
    signal vsync : std_logic;

    signal audio : std_logic_vector(10 downto 0);
    signal pwm_accumulator : std_logic_vector(12 downto 0);

    signal kbd_intr : std_logic;
    signal kbd_scancode : std_logic_vector(7 downto 0);
    signal joyPCFRLDU : std_logic_vector(7 downto 0);

    signal dbg_cpu_addr : std_logic_vector(15 downto 0);

    -- video signals
    signal vga_g_i : std_logic_vector(5 downto 0);
    signal vga_r_i : std_logic_vector(5 downto 0);
    signal vga_b_i : std_logic_vector(5 downto 0);
    signal vga_r_o : std_logic_vector(5 downto 0);
    signal vga_g_o : std_logic_vector(5 downto 0);
    signal vga_b_o : std_logic_vector(5 downto 0);
    signal vga_hs_o : std_logic;
    signal vga_vs_o : std_logic;

    component vga_scandoubler is
        port (
            clkvideo : in std_logic;
            clkvga : in std_logic; -- has to be double of clkvideo
            enable_scandoubling : in std_logic;
            disable_scaneffect : in std_logic;
            ri : in std_logic_vector(5 downto 0);
            gi : in std_logic_vector(5 downto 0);
            bi : in std_logic_vector(5 downto 0);
            hsync_ext_n : in std_logic;
            vsync_ext_n : in std_logic;
            csync_ext_n : in std_logic;
            ro : out std_logic_vector(5 downto 0);
            go : out std_logic_vector(5 downto 0);
            bo : out std_logic_vector(5 downto 0);
            hsync : out std_logic;
            vsync : out std_logic
        );
    end component;

    component clk_wiz_0
        port (
            clk_out1 : out std_logic;
            clk_out2 : out std_logic;
            reset : in std_logic;
            locked : out std_logic;
            clk_in1 : in std_logic
        );
    end component;

begin

    reset <= '0'; --not reset_n;

    -- Clock 12.288MHz for pooyan core, 14.318MHz for sound_board
    u_clocks : clk_wiz_0
    port map(
        clk_in1 => clk,
        reset => reset,
        clk_out1 => clock_12,
        clk_out2 => clock_14,
        locked => open --pll_locked
    );

    -- Pooyan
    pooyan : entity work.pooyan
        port map(
            clock_12 => clock_12,
            clock_14 => clock_14,
            reset => reset,

            -- tv15Khz_mode => tv15Khz_mode,
            video_r => r,
            video_g => g,
            video_b => b,
            video_csync => csync,
            video_blankn => blankn,
            -- video_hs     => open, --hsync, -- not tested
            -- video_vs     => open, --vsync, -- not tested
            video_hs => hsync,
            video_vs => vsync,

            audio_out => audio,

            dip_switch_1 => X"FF", -- Coinage_B / Coinage_A
            dip_switch_2 => X"7F", -- Sound(8)/Difficulty(7-5)/Bonus(4)/Cocktail(3)/lives(2-1)
            -- dip_switch_2 => sw(7 downto 0), 

            start2 => joyPCFRLDU(7),
            start1 => joyPCFRLDU(6),
            coin1 => joyPCFRLDU(5),

            fire1 => joyPCFRLDU(4),
            right1 => joyPCFRLDU(3),
            left1 => joyPCFRLDU(2),
            down1 => joyPCFRLDU(1),
            up1 => joyPCFRLDU(0),

            fire2 => joyPCFRLDU(4),
            right2 => joyPCFRLDU(3),
            left2 => joyPCFRLDU(2),
            down2 => joyPCFRLDU(1),
            up2 => joyPCFRLDU(0),

            dbg_cpu_addr => dbg_cpu_addr
        );

    ---- adapt video to 4bits/color only
    --vga_r <= r&'0'  when blankn = '1' else "0000";
    --vga_g <= g&'0'  when blankn = '1' else "0000";
    --vga_b <= b&"00" when blankn = '1' else "0000";

    ---- synchro composite/ synchro horizontale
    --vga_hs <= csync;
    ---- vga_hs <= csync when tv15Khz_mode = '1' else hsync;
    ---- commutation rapide / synchro verticale
    --vga_vs <= '1';
    ---- vga_vs <= '1'   when tv15Khz_mode = '1' else vsync;
    -- VGA 
    -- adapt video to 6bits/color only and blank
    vga_r_i <= r & r when blankn = '1' else "000000";
    vga_g_i <= g & g when blankn = '1' else "000000";
    vga_b_i <= b & b & b when blankn = '1' else "000000";

    -- vga scandoubler
    scandoubler : vga_scandoubler
    port map(
        --input
        clkvideo => clock_6,
        clkvga => clock_12, -- has to be double of clkvideo
        enable_scandoubling => '1',
        disable_scaneffect => '1', -- 1 to disable scanlines
        ri => vga_r_i,
        gi => vga_g_i,
        bi => vga_b_i,
        hsync_ext_n => hsync,
        vsync_ext_n => vsync,
        csync_ext_n => csync,
        --output
        ro => vga_r_o,
        go => vga_g_o,
        bo => vga_b_o,
        hsync => vga_hs_o,
        vsync => vga_vs_o
    );

    --VGA
    -- adapt video to 4 bits/color only
    vga_r <= vga_r_o (5 downto 2);
    vga_g <= vga_g_o (5 downto 2);
    vga_b <= vga_b_o (5 downto 2);
    vga_hs <= vga_hs_o;
    vga_vs <= vga_vs_o;
    -- get scancode from keyboard
    process (reset, clock_12)
    begin
        if reset = '1' then
            clock_6 <= '0';
        else
            if rising_edge(clock_12) then
                clock_6 <= not clock_6;
            end if;
        end if;
    end process;

    keyboard : entity work.io_ps2_keyboard
        port map(
            clk => clock_6, -- synchrounous clock with core
            kbd_clk => ps2_clk,
            kbd_dat => ps2_dat,
            interrupt => kbd_intr,
            scancode => kbd_scancode
        );

    -- translate scancode to joystick
    joystick : entity work.kbd_joystick
        port map(
            clk => clock_6, -- synchrounous clock with core
            kbdint => kbd_intr,
            kbdscancode => std_logic_vector(kbd_scancode),
            joyPCFRLDU => joyPCFRLDU
        );

    -- pwm sound output

    process (clock_14) -- use same clock as pooyan_sound_board
    begin
        if rising_edge(clock_14) then
            pwm_accumulator <= std_logic_vector(unsigned('0' & pwm_accumulator(11 downto 0)) + unsigned(audio & "00"));
        end if;
    end process;

    -- active-low shutdown pin
    O_PMODAMP2_SHUTD <= sw(14);
    -- gain pin is driven high there is a 6 dB gain, low is a 12 dB gain 
    O_PMODAMP2_GAIN <= sw(15);

    --pwm_audio_out_l <= pwm_accumulator(12);
    --pwm_audio_out_r <= pwm_accumulator(12); 
    O_PMODAMP2_AIN <= pwm_accumulator(12);

end struct;
