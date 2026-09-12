-- Exhaustive self-checking testbench for ual_8 (complete ALU, sequential).
--
-- Space: OP in 0..15 x A in 0..255 x B in 0..255 = 1,048,576 operations.
-- Unary opcodes (NOT, shifts, ROL, SQRT) and unused opcodes C..F are also swept
-- over B, which checks that B has no effect on them.
--
-- Handshake used (same as proc_8): OP/A/B and start='1' are driven together and
-- kept stable until done='1'; start is then held for 0, 1 or 2 more edges
-- (selected by (A+B+OP) mod 3; proc_8 holds it for exactly 1) and released.
--
-- Latency, counted in rising edges from the edge that samples start='1' in IDLE
-- (tick 1) until done='1' is visible, derived from the RTL:
--   combinational ops : IDLE->RUN_COMB, RUN_COMB (res/C/V), DONE_STATE (Z/N, done)  = 3
--   MUL  : IDLE->RUN_MUL (multiplier captures), 8 CALC, RUN_MUL capture, DONE_STATE = 11
--   SQRT : IDLE->RUN_SQRT (sqrt captures), 8 COMPUTE, FINISH, capture, DONE_STATE    = 12
-- RESULT/Z/N/C/V must keep their previous values up to tick LATENCY-2.
-- After release, done falls one edge later and RESULT/flags are kept.

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_ual_8 is
end entity tb_ual_8;

architecture sim of tb_ual_8 is
    constant HALF_PERIOD : time := 5 ns;
    constant TIMEOUT     : time := 500 ms;

    signal clk     : std_logic := '0';
    signal running : boolean   := true;
    signal reset   : std_logic := '0';
    signal start   : std_logic := '0';
    signal a       : std_logic_vector(7 downto 0) := (others => '0');
    signal b       : std_logic_vector(7 downto 0) := (others => '0');
    signal op      : std_logic_vector(3 downto 0) := (others => '0');
    signal result  : std_logic_vector(7 downto 0);
    signal z, n, c, v, done : std_logic;
begin

    clk <= not clk after HALF_PERIOD when running else '0';

    dut : entity work.ual_8
        port map (clk => clk, reset => reset, start => start, A => a, B => b, OP => op,
                  RESULT => result, Z => z, N => n, C => c, V => v, done => done);

    watchdog : process
    begin
        wait until not running for TIMEOUT;
        assert not running report "TB_TIMEOUT tb_ual_8" severity failure;
        wait;
    end process watchdog;

    stim : process
        constant EXPECTED_VECTORS : natural := 16 * 256 * 256;
        variable vectors  : natural := 0;
        variable directed : natural := 0;
        variable errors   : natural := 0;
        variable cur      : alu_ref_t := ALU_RESET_STATE;  -- expected RESULT/flags on the outputs

        procedure tick is
        begin
            wait until rising_edge(clk);
            wait until falling_edge(clk);
        end procedure;

        impure function outputs_match(e : alu_ref_t) return boolean is
        begin
            return result = to_slv(e.result, 8) and z = e.z and n = e.n and c = e.c and v = e.v;
        end function;

        procedure check_outputs(e : alu_ref_t; iop, ia, ib : natural; tag : string) is
        begin
            if not outputs_match(e) then
                tb_error(errors, tag & " OP=" & hex(iop, 1) & " A=" & hex(ia, 2) & " B=" & hex(ib, 2) &
                         " got R=" & hex(result) & " ZNCV=" & sl_char(z) & sl_char(n) & sl_char(c) & sl_char(v) &
                         " exp R=" & hex(e.result, 2) & " ZNCV=" & flags_str(e));
            end if;
        end procedure;

        -- One ALU operation with the processor handshake; updates cur
        procedure run_op(iop, ia, ib : natural; hold : natural) is
            constant LAT : positive  := alu_latency(iop);
            constant EXP : alu_ref_t := ref_alu(iop, ia, ib);
        begin
            op    <= to_slv(iop, 4);
            a     <= to_slv(ia, 8);
            b     <= to_slv(ib, 8);
            start <= '1';
            for e in 1 to LAT loop
                tick;
                if e < LAT then
                    if done /= '0' then
                        report "FATAL: done asserted early at tick " & integer'image(e) &
                               " OP=" & hex(iop, 1) & " A=" & hex(ia, 2) & " B=" & hex(ib, 2) severity failure;
                    end if;
                    if e <= LAT - 2 then
                        check_outputs(cur, iop, ia, ib, "outputs changed while busy:");
                    end if;
                elsif done /= '1' then
                    report "FATAL: done not asserted at tick " & integer'image(LAT) &
                           " OP=" & hex(iop, 1) & " A=" & hex(ia, 2) & " B=" & hex(ib, 2) severity failure;
                end if;
            end loop;
            cur := EXP;
            check_outputs(cur, iop, ia, ib, "result/flags:");
            for h in 1 to hold loop
                tick;
                if done /= '1' then
                    tb_error(errors, "done dropped while start held, OP=" & hex(iop, 1));
                end if;
                check_outputs(cur, iop, ia, ib, "outputs changed while start held:");
            end loop;
            start <= '0';
            tick;
            if done /= '0' then
                tb_error(errors, "done still high one edge after release, OP=" & hex(iop, 1));
            end if;
            check_outputs(cur, iop, ia, ib, "outputs changed after release:");
        end procedure;

    begin
        -------------------------------------------------------------------------
        -- D1: reset held low while start='1' with a non-trivial ADD request
        -------------------------------------------------------------------------
        op    <= to_slv(OP_ADD, 4);
        a     <= x"FF";
        b     <= x"FF";
        start <= '1';
        for i in 1 to 4 loop
            tick;
            directed := directed + 1;
            if done /= '0' then
                tb_error(errors, "reset: done not low at tick " & integer'image(i));
            end if;
            -- Z='0' while RESULT=0: Z is only computed in DONE_STATE
            check_outputs(ALU_RESET_STATE, OP_ADD, 255, 255, "reset:");
        end loop;
        start <= '0';
        reset <= '1';
        tick;

        -------------------------------------------------------------------------
        -- Exhaustive sweep of all opcodes
        -------------------------------------------------------------------------
        for iop in 0 to 15 loop
            for ia in 0 to 255 loop
                for ib in 0 to 255 loop
                    run_op(iop, ia, ib, (ia + ib + iop) mod 3);
                    vectors := vectors + 1;
                end loop;
            end loop;
        end loop;

        -------------------------------------------------------------------------
        -- CHAR-1: start pulse shorter than the operation (outside the protocol).
        -- RESULT/flags are updated but done never rises; the ALU returns to IDLE.
        -------------------------------------------------------------------------
        op    <= to_slv(OP_ADD, 4);
        a     <= x"01";
        b     <= x"02";
        start <= '1';
        tick;
        start <= '0';
        for i in 2 to 10 loop
            tick;
            if done /= '0' then
                tb_error(errors, "CHAR-1: done rose after a 1-cycle start pulse at tick " & integer'image(i));
            end if;
        end loop;
        cur := ref_alu(OP_ADD, 1, 2);
        check_outputs(cur, OP_ADD, 1, 2, "CHAR-1 outputs:");
        run_op(OP_SUB, 16#05#, 16#07#, 1);  -- ALU usable again; C=1 (borrow), N=1
        directed := directed + 2;

        -------------------------------------------------------------------------
        -- CHAR-2: combinational opcodes do not register A/B at the start edge;
        -- they are read on the RUN_COMB edge (tick 2), hence the stability rule.
        -------------------------------------------------------------------------
        op    <= to_slv(OP_ADD, 4);
        a     <= x"10";
        b     <= x"01";
        start <= '1';
        tick;
        a <= x"20";
        tick;
        tick;
        cur := ref_alu(OP_ADD, 16#20#, 16#01#);
        if done /= '1' then
            tb_error(errors, "CHAR-2: done not asserted at tick 3");
        end if;
        check_outputs(cur, OP_ADD, 16#20#, 16#01#, "CHAR-2 (operand read at tick 2):");
        start <= '0';
        tick;
        directed := directed + 1;

        -------------------------------------------------------------------------
        -- CHAR-3: MUL operands are captured by mult_shift_add on the start edge
        -------------------------------------------------------------------------
        op    <= to_slv(OP_MUL, 4);
        a     <= x"03";
        b     <= x"05";
        start <= '1';
        tick;
        a <= x"07";
        b <= x"09";
        for i in 2 to 11 loop
            tick;
        end loop;
        cur := ref_alu(OP_MUL, 3, 5);
        if done /= '1' then
            tb_error(errors, "CHAR-3: done not asserted at tick 11");
        end if;
        check_outputs(cur, OP_MUL, 3, 5, "CHAR-3 (operands captured at tick 1):");
        start <= '0';
        tick;
        directed := directed + 1;

        -------------------------------------------------------------------------
        -- D2: asynchronous reset during a MUL clears RESULT/flags/done at once;
        -- the multiplier sub-unit is reset too and the next operations succeed.
        -------------------------------------------------------------------------
        op    <= to_slv(OP_MUL, 4);
        a     <= x"FF";
        b     <= x"FF";
        start <= '1';
        for i in 1 to 5 loop
            tick;
        end loop;
        wait for 2 ns;
        reset <= '0';
        wait for 1 ns;
        cur := ALU_RESET_STATE;
        if done /= '0' then
            tb_error(errors, "D2: done not cleared by asynchronous reset");
        end if;
        check_outputs(cur, OP_MUL, 255, 255, "D2 async reset:");
        start <= '0';
        wait until falling_edge(clk);
        tick;
        reset <= '1';
        tick;
        run_op(OP_MUL, 13, 11, 1);          -- 143 = 0x8F, N=1
        run_op(OP_SQRT, 200, 0, 1);         -- 14
        run_op(OP_ADD, 16#80#, 16#80#, 0);  -- 0x00, Z=1, C=1, V=1
        directed := directed + 4;

        running <= false;
        tb_summary("tb_ual_8", vectors, EXPECTED_VECTORS, directed, errors);
        wait;
    end process stim;

end architecture sim;
