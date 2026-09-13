library ieee;
use ieee.std_logic_1164.all;

-- Terasic DE1 (Cyclone II EP2C20F484C7) top-level wrapper for the validated
-- proc_8 processor. Board-only glue: a clock divider that slows the core down
-- to human speed and a 7-segment decoder for the result register.
-- rtl/proc_8.vhd and its sub-units are instantiated unmodified.
--
-- Clocking: proc_8 has no clock-enable input. At 50 MHz its fixed program
-- reaches the 11th result 110 clock edges after reset release, i.e. in 2.2 us,
-- so only the final value would ever be visible. The wrapper therefore drives
-- the core from core_clk, a register output toggled every CORE_CLK_HALF_PERIOD
-- cycles of CLOCK_50 (default 3_125_000 -> 8 Hz). An 8-edge ALU instruction
-- then takes 1 s and the program reaches HALT after about 14 s.
--
-- Reset: KEY0 (active low) goes through a two-register synchronizer that
-- asserts rst_sync_n asynchronously and releases it on the second CLOCK_50
-- rising edge after KEY0 goes high. rst_sync_n clears the divider and resets
-- proc_8, so every reset release inside the design is a CLOCK_50 register
-- output. core_clk is held at '0' during reset and its first rising edge
-- occurs CORE_CLK_HALF_PERIOD cycles (62.5 ms) after rst_sync_n is released,
-- long after proc_8 has left reset.
entity proc8_de1_top is
    generic (
        CORE_CLK_HALF_PERIOD : positive := 3_125_000  -- CLOCK_50 cycles per core_clk half period
    );
    port (
        CLOCK_50 : in  std_logic;                     -- 50 MHz board clock
        KEY0     : in  std_logic;                     -- KEY(0), active-low reset
        LEDR     : out std_logic_vector(7 downto 0);  -- result register R
        LEDG     : out std_logic_vector(3 downto 0);  -- LEDG(0)=Z, (1)=N, (2)=C, (3)=V
        HEX0     : out std_logic_vector(6 downto 0);  -- R(3 downto 0) in hexadecimal
        HEX1     : out std_logic_vector(6 downto 0)   -- R(7 downto 4) in hexadecimal
    );
end entity proc8_de1_top;

architecture rtl of proc8_de1_top is

    signal rst_meta_n : std_logic := '0';
    signal rst_sync_n : std_logic := '0';

    signal div_count : integer range 0 to CORE_CLK_HALF_PERIOD - 1 := 0;
    signal core_clk  : std_logic := '0';

    signal R_core : std_logic_vector(7 downto 0);
    signal Z_core : std_logic;
    signal N_core : std_logic;
    signal C_core : std_logic;
    signal V_core : std_logic;

    -- 7-segment decoder, DE1 segments active low, bit 0 = segment a.
    function hex7seg(x : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable s : std_logic_vector(6 downto 0);
    begin
        case x is
            when "0000" => s := "1000000"; -- 0
            when "0001" => s := "1111001"; -- 1
            when "0010" => s := "0100100"; -- 2
            when "0011" => s := "0110000"; -- 3
            when "0100" => s := "0011001"; -- 4
            when "0101" => s := "0010010"; -- 5
            when "0110" => s := "0000010"; -- 6
            when "0111" => s := "1111000"; -- 7
            when "1000" => s := "0000000"; -- 8
            when "1001" => s := "0010000"; -- 9
            when "1010" => s := "0001000"; -- A
            when "1011" => s := "0000011"; -- b
            when "1100" => s := "1000110"; -- C
            when "1101" => s := "0100001"; -- d
            when "1110" => s := "0000110"; -- E
            when others => s := "0001110"; -- F
        end case;
        return s;
    end function;

begin

    -- Reset synchronizer: asynchronous assertion, synchronous deassertion.
    reset_synchronizer : process (CLOCK_50, KEY0)
    begin
        if KEY0 = '0' then
            rst_meta_n <= '0';
            rst_sync_n <= '0';
        elsif rising_edge(CLOCK_50) then
            rst_meta_n <= '1';
            rst_sync_n <= rst_meta_n;
        end if;
    end process reset_synchronizer;

    -- Synchronous divider in the CLOCK_50 domain; core_clk is a register output.
    clock_divider : process (CLOCK_50, rst_sync_n)
    begin
        if rst_sync_n = '0' then
            div_count <= 0;
            core_clk  <= '0';
        elsif rising_edge(CLOCK_50) then
            if div_count = CORE_CLK_HALF_PERIOD - 1 then
                div_count <= 0;
                core_clk  <= not core_clk;
            else
                div_count <= div_count + 1;
            end if;
        end if;
    end process clock_divider;

    U_PROC : entity work.proc_8
        port map (
            clk   => core_clk,
            reset => rst_sync_n,
            R_out => R_core,
            Z_out => Z_core,
            N_out => N_core,
            C_out => C_core,
            V_out => V_core
        );

    LEDR    <= R_core;
    LEDG(0) <= Z_core;
    LEDG(1) <= N_core;
    LEDG(2) <= C_core;
    LEDG(3) <= V_core;

    HEX0 <= hex7seg(R_core(3 downto 0));
    HEX1 <= hex7seg(R_core(7 downto 4));

end architecture rtl;
