-- Exhaustive self-checking testbench for addsub_8 (combinational).
--
-- Space: sub in {0,1} x A in 0..255 x B in 0..255 = 131,072 vectors.
-- Characterized semantics of the unit (not of ual_8):
--   sub='0': S = (A+B) mod 256, C = carry out (A+B > 255)
--   sub='1': S = (A-B) mod 256, C = raw adder carry = NOT borrow (A >= B)
--   V = two's complement overflow of the signed operation

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_addsub_8 is
end entity tb_addsub_8;

architecture sim of tb_addsub_8 is
    signal a   : std_logic_vector(7 downto 0) := (others => '0');
    signal b   : std_logic_vector(7 downto 0) := (others => '0');
    signal sub : std_logic := '0';
    signal s   : std_logic_vector(7 downto 0);
    signal c   : std_logic;
    signal v   : std_logic;
begin

    dut : entity work.addsub_8
        port map (A => a, B => b, sub => sub, S => s, C => c, V => v);

    stim : process
        constant EXPECTED_VECTORS : natural := 2 * 256 * 256;
        variable vectors  : natural := 0;
        variable errors   : natural := 0;
        variable ref_s    : natural;
        variable ref_c    : std_logic;
        variable ref_v    : std_logic;
    begin
        for m in 0 to 1 loop
            for ia in 0 to 255 loop
                for ib in 0 to 255 loop
                    a   <= to_slv(ia, 8);
                    b   <= to_slv(ib, 8);
                    sub <= to_sl(m = 1);
                    wait for 1 ns;

                    if m = 0 then
                        ref_s := wrap8(ia + ib);
                        ref_c := to_sl(ia + ib > 255);
                        ref_v := signed_overflow(to_s8(ia) + to_s8(ib));
                    else
                        ref_s := wrap8(ia - ib);
                        ref_c := to_sl(ia >= ib);
                        ref_v := signed_overflow(to_s8(ia) - to_s8(ib));
                    end if;

                    vectors := vectors + 1;
                    if s /= to_slv(ref_s, 8) or c /= ref_c or v /= ref_v then
                        tb_error(errors, "sub=" & integer'image(m) &
                                 " A=" & hex(ia, 2) & " B=" & hex(ib, 2) &
                                 " got S=" & hex(s) & " C=" & sl_char(c) & " V=" & sl_char(v) &
                                 " exp S=" & hex(ref_s, 2) & " C=" & sl_char(ref_c) & " V=" & sl_char(ref_v));
                    end if;
                end loop;
            end loop;
        end loop;

        tb_summary("tb_addsub_8", vectors, EXPECTED_VECTORS, 0, errors);
        wait;
    end process stim;

end architecture sim;
