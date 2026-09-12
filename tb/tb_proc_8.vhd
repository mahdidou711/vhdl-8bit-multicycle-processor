-- Cycle-accurate self-checking testbench for proc_8 (processor top level).
--
-- proc_8 only exposes R and Z/N/C/V, and its ROM/PC/FSM are not reachable from a
-- VHDL-93 testbench. The testbench therefore runs an instruction-level model of
-- the documented ROM program, computes each result with the tb_pkg reference ALU,
-- and compares the five outputs against the model on EVERY clock edge.
--
-- Edge costs derived from the proc_8 FSM (L = alu_latency(op), see tb_ual_8.vhd):
--   LOAD_A / LOAD_B : FETCH, DECODE, LOAD_IMM                             = 3 edges
--   ALU opcode      : FETCH, DECODE (start<='1'), L edges until ual_done,
--                     WAIT_UAL sees done, CAPTURE (R/flags), WRITEBACK      = L + 5 edges
--   HALT            : FETCH, DECODE, then HALT forever
-- Outputs change only on CAPTURE edges and on reset.
--
-- Generic RUN_TO_HALT selects the scenario:
--   false (program) : reset, partial run, asynchronous reset while an ALU operation
--                     is pending, full run of the 11 results, then the clock is
--                     stopped BEFORE the FETCH of ROM[15]. The HALT boundary is
--                     covered by the other scenario, not skipped.
--   true  (halt)    : reset, full run of the 11 results, FETCH/DECODE of ROM[15]
--                     (0xFF), then 200 edges of HALT with frozen outputs (more than
--                     one complete program pass, so a restart would be detected).
--                     On the original RTL this reproduces known defect KD-001:
--                     FETCH executes PC <= PC + 1 with PC = 15 while PC is declared
--                     "integer range 0 to 15" (rtl/proc_8.vhd:145), which is a
--                     bound check failure in simulation.

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_proc_8 is
    generic (RUN_TO_HALT : boolean := false);
end entity tb_proc_8;

architecture sim of tb_proc_8 is
    constant HALF_PERIOD        : time     := 5 ns;
    constant TIMEOUT            : time     := 1 ms;
    constant HALT_OBSERVE_EDGES : positive := 200;
    constant N_RESULTS          : positive := 11;

    -- Program transcribed from the ROM constant documented in rtl/proc_8.vhd
    type program_t is array (0 to 15) of natural range 0 to 255;
    constant PROGRAM : program_t := (
        16#10#, 16#19#,                          -- LOAD_A 0x19
        16#11#, 16#07#,                          -- LOAD_B 0x07
        16#00#, 16#01#, 16#02#, 16#03#, 16#04#,  -- ADD SUB AND OR XOR
        16#06#, 16#07#, 16#08#, 16#09#,          -- SHL SHR SAR ROL
        16#0A#, 16#0B#,                          -- MUL SQRT
        16#FF#);                                 -- HALT

    -- Hand-derived trace for A = 0x19 = 0001_1001, B = 0x07 = 0000_0111.
    -- Used only to cross-check the model; the DUT is compared against the model.
    type results_t is array (1 to N_RESULTS) of natural range 0 to 255;
    type flags_t   is array (1 to N_RESULTS) of string(1 to 4);  -- "ZNCV"
    constant HAND_RESULTS : results_t := (
        16#20#,   -- ADD  25 + 7 = 32
        16#12#,   -- SUB  25 - 7 = 18, no borrow
        16#01#,   -- AND  0000_0001
        16#1F#,   -- OR   0001_1111
        16#1E#,   -- XOR  0001_1110
        16#32#,   -- SHL  0011_0010
        16#0C#,   -- SHR  0000_1100
        16#0C#,   -- SAR  0000_1100 (A positive)
        16#32#,   -- ROL  0011_0010 (bit 7 = 0 re-enters bit 0)
        16#AF#,   -- MUL  25 * 7 = 175
        16#05#);  -- SQRT floor(sqrt(25)) = 5
    constant HAND_FLAGS : flags_t := (
        "0000", "0000", "0000", "0000", "0000",
        "0000",   -- SHL: C = bit 7 of A = 0
        "0010",   -- SHR: C = bit 0 of A = 1
        "0010",   -- SAR: C = bit 0 of A = 1
        "0000",   -- ROL: C = bit 7 of A = 0
        "0100",   -- MUL: N = bit 7 of 0xAF
        "0000");

    signal clk     : std_logic := '0';
    signal running : boolean   := true;
    signal reset   : std_logic := '0';
    signal r_out   : std_logic_vector(7 downto 0);
    signal z_out, n_out, c_out, v_out : std_logic;
begin

    clk <= not clk after HALF_PERIOD when running else '0';

    dut : entity work.proc_8
        port map (clk => clk, reset => reset, R_out => r_out,
                  Z_out => z_out, N_out => n_out, C_out => c_out, V_out => v_out);

    watchdog : process
    begin
        wait until not running for TIMEOUT;
        assert not running report "TB_TIMEOUT tb_proc_8" severity failure;
        wait;
    end process watchdog;

    stim : process
        variable errors  : natural := 0;
        variable edges   : natural := 0;   -- compared clock edges
        variable commits : natural := 0;   -- verified CAPTURE edges, all runs
        variable cur     : alu_ref_t := ALU_RESET_STATE;
        -- Instruction-level model state (PC deliberately unconstrained)
        variable pc, ir, reg_a, reg_b, opc, commit : natural := 0;

        procedure tick is
        begin
            wait until rising_edge(clk);
            wait until falling_edge(clk);
        end procedure;

        impure function outputs_str return string is
        begin
            return "R=" & hex(r_out) & " ZNCV=" & sl_char(z_out) & sl_char(n_out) & sl_char(c_out) & sl_char(v_out);
        end function;

        impure function outputs_match return boolean is
        begin
            return r_out = to_slv(cur.result, 8) and z_out = cur.z and n_out = cur.n and
                   c_out = cur.c and v_out = cur.v;
        end function;

        -- One rising edge, then compare the outputs with the model
        procedure step(state : string) is
        begin
            tick;
            edges := edges + 1;
            if not outputs_match then
                tb_error(errors, "edge " & integer'image(edges) & " (" & state & ", model PC=" &
                         integer'image(pc) & ") got " & outputs_str &
                         " exp R=" & hex(cur.result, 2) & " ZNCV=" & flags_str(cur));
            end if;
        end procedure;

        -- Run the program from PC=0 and return right after the n-th CAPTURE edge
        procedure run_program(n_commits : positive) is
        begin
            pc     := 0;
            reg_a  := 0;
            reg_b  := 0;
            commit := 0;
            loop
                ir := PROGRAM(pc);
                pc := pc + 1;
                step("FETCH");
                step("DECODE");
                if ir = 16#FF# then
                    report "FATAL: model reached HALT before commit " & integer'image(n_commits) severity failure;
                elsif ir = 16#10# or ir = 16#11# then
                    if ir = 16#10# then
                        reg_a := PROGRAM(pc);
                    else
                        reg_b := PROGRAM(pc);
                    end if;
                    pc := pc + 1;
                    step("LOAD_IMM");
                else
                    opc := ir mod 16;
                    for i in 1 to alu_latency(opc) + 1 loop
                        step("WAIT_UAL");
                    end loop;
                    cur := ref_alu(opc, reg_a, reg_b);
                    step("CAPTURE");
                    commit  := commit + 1;
                    commits := commits + 1;
                    report "COMMIT " & integer'image(commit) & " ROM[" & integer'image(pc - 1) & "]=" &
                           hex(ir, 2) & " A=" & hex(reg_a, 2) & " B=" & hex(reg_b, 2) &
                           " DUT " & outputs_str & " at edge " & integer'image(edges);
                    if cur.result /= HAND_RESULTS(commit) or flags_str(cur) /= HAND_FLAGS(commit) then
                        tb_error(errors, "model disagrees with hand-derived trace at commit " &
                                 integer'image(commit));
                    end if;
                    exit when commit = n_commits;
                    step("WRITEBACK");
                end if;
            end loop;
        end procedure;

    begin
        -- R1: reset held low for 5 edges, outputs at reset state
        reset <= '0';
        for i in 1 to 5 loop
            step("RESET");
        end loop;
        reset <= '1';

        if not RUN_TO_HALT then
            -- P1: run up to the 4th result (OR), then enter the XOR instruction
            run_program(4);
            step("WRITEBACK");
            ir := PROGRAM(pc);
            pc := pc + 1;
            step("FETCH");
            step("DECODE");
            step("WAIT_UAL");
            step("WAIT_UAL");

            -- R2: asynchronous reset between edges while the ALU is busy
            wait for 2 ns;
            reset <= '0';
            wait for 1 ns;
            cur := ALU_RESET_STATE;
            if not outputs_match then
                tb_error(errors, "asynchronous reset did not clear outputs, got " & outputs_str);
            end if;
            wait until falling_edge(clk);
            for i in 1 to 3 loop
                step("RESET");
            end loop;
            reset <= '1';

            -- P2: complete program from PC=0; stop the clock before FETCH of ROM[15]
            run_program(N_RESULTS);
            step("WRITEBACK");
            running <= false;
            report "program scenario stops before FETCH of ROM[15]; HALT boundary is tested by RUN_TO_HALT=true";
            tb_summary("tb_proc_8_program", commits, 4 + N_RESULTS, edges, errors);
        else
            run_program(N_RESULTS);
            step("WRITEBACK");
            report "KD-001 PROBE: " & integer'image(N_RESULTS) &
                   " results verified; next rising edge is FETCH of ROM[15] (HALT) with PC=15";
            ir := PROGRAM(pc);
            pc := pc + 1;
            step("FETCH ROM[15]");
            step("DECODE HALT");
            for i in 1 to HALT_OBSERVE_EDGES loop
                step("HALT");
            end loop;
            running <= false;
            tb_summary("tb_proc_8_halt", commits, N_RESULTS, edges, errors);
        end if;
        wait;
    end process stim;

end architecture sim;
