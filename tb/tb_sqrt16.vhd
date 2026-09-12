-- Exhaustive self-checking testbench for sqrt16 (sequential).
--
-- Space: X_in in 0..65535 = 65,536 roots.
-- Reference: property check r*r <= X < (r+1)*(r+1), so the oracle does not
-- re-implement the non-restoring algorithm of the RTL.
--
-- Protocol characterized from the RTL (reset active low, asynchronous):
--   * the rising edge that samples start='1' in IDLE captures X_in (tick 1);
--   * 8 COMPUTE edges and 1 FINISH edge follow; done='1' after tick LATENCY = 10;
--   * R_out keeps the previous root until the FINISH edge;
--   * done stays '1' while start='1' (WAIT_LOW), then falls one edge after start='0';
--   * R_out keeps the root after done falls.
-- Start mode per root is selected by X mod 4 (pulse, or held +0/+1/+2 edges).
-- X_in is replaced by its complement after the capture edge when bit 2 of X is set.

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_sqrt16 is
end entity tb_sqrt16;

architecture sim of tb_sqrt16 is
    constant HALF_PERIOD : time     := 5 ns;
    constant LATENCY     : positive := 10;
    constant TIMEOUT     : time     := 20 ms;

    signal clk     : std_logic := '0';
    signal running : boolean   := true;
    signal reset   : std_logic := '0';
    signal start   : std_logic := '0';
    signal x_in    : std_logic_vector(15 downto 0) := (others => '0');
    signal r_out   : std_logic_vector(7 downto 0);
    signal done    : std_logic;
begin

    clk <= not clk after HALF_PERIOD when running else '0';

    dut : entity work.sqrt16
        port map (clk => clk, reset => reset, start => start,
                  X_in => x_in, R_out => r_out, done => done);

    watchdog : process
    begin
        wait until not running for TIMEOUT;
        assert not running report "TB_TIMEOUT tb_sqrt16" severity failure;
        wait;
    end process watchdog;

    stim : process
        constant EXPECTED_VECTORS : natural := 65536;
        variable vectors  : natural := 0;
        variable directed : natural := 0;
        variable errors   : natural := 0;

        procedure tick is
        begin
            wait until rising_edge(clk);
            wait until falling_edge(clk);
        end procedure;

        procedure run_sqrt(x : natural; mode : integer; scramble : boolean) is
            constant PREV : std_logic_vector(7 downto 0) := r_out;
            constant CTX  : string := " X=" & hex(x, 4);
            variable root : std_logic_vector(7 downto 0);
        begin
            x_in  <= to_slv(x, 16);
            start <= '1';
            for e in 1 to LATENCY loop
                tick;
                if e = 1 then
                    if mode < 0 then
                        start <= '0';
                    end if;
                    if scramble then
                        x_in <= to_slv(65535 - x, 16);
                    end if;
                end if;
                if e < LATENCY then
                    if done /= '0' then
                        report "FATAL: done asserted early at tick " & integer'image(e) & CTX severity failure;
                    end if;
                    if r_out /= PREV then
                        tb_error(errors, "R_out changed before FINISH at tick " & integer'image(e) & CTX);
                    end if;
                elsif done /= '1' then
                    report "FATAL: done not asserted at tick " & integer'image(LATENCY) & CTX severity failure;
                end if;
            end loop;
            root := r_out;
            if to_nat(root) < 0 or not is_isqrt(x, to_nat(root)) then
                tb_error(errors, "root" & CTX & " got " & hex(root));
            end if;
            if mode >= 0 then
                for h in 1 to mode loop
                    tick;
                    if done /= '1' or r_out /= root then
                        tb_error(errors, "held start: done/R_out not stable" & CTX);
                    end if;
                end loop;
                start <= '0';
            end if;
            tick;
            if done /= '0' or r_out /= root then
                tb_error(errors, "after release: expected done=0 and R_out kept" & CTX);
            end if;
        end procedure;

    begin
        -- D1: reset held low with start='1': nothing is captured
        start <= '1';
        x_in  <= x"FFFF";
        for i in 1 to 4 loop
            tick;
            directed := directed + 1;
            if done /= '0' or r_out /= x"00" then
                tb_error(errors, "reset: outputs not cleared at tick " & integer'image(i));
            end if;
        end loop;
        start <= '0';
        reset <= '1';
        tick;

        -- Exhaustive roots
        for x in 0 to 65535 loop
            run_sqrt(x, (x mod 4) - 1, (x / 4) mod 2 = 1);
            vectors := vectors + 1;
        end loop;

        -- D2: asynchronous reset during COMPUTE clears done and R_out immediately
        x_in  <= x"1000";
        start <= '1';
        for i in 1 to 5 loop
            tick;
        end loop;
        wait for 2 ns;
        reset <= '0';
        wait for 1 ns;
        directed := directed + 1;
        if done /= '0' or r_out /= x"00" then
            tb_error(errors, "async reset during COMPUTE did not clear outputs");
        end if;
        start <= '0';
        wait until falling_edge(clk);
        tick;
        reset <= '1';
        tick;

        -- D3: recovery after reset
        run_sqrt(65535, 0, false);
        run_sqrt(16#4000#, -1, false);
        directed := directed + 2;

        running <= false;
        tb_summary("tb_sqrt16", vectors, EXPECTED_VECTORS, directed, errors);
        wait;
    end process stim;

end architecture sim;
