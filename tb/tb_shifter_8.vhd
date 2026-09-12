-- Exhaustive self-checking testbench for shifter_8 (combinational).
--
-- Space: OP in 0..3 x A in 0..255 = 1,024 vectors.
-- OP encoding: "00" SHL (C=A7), "01" SHR (C=A0), "10" SAR (C=A0), "11" ROL (C=A7).

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_shifter_8 is
end entity tb_shifter_8;

architecture sim of tb_shifter_8 is
    signal a  : std_logic_vector(7 downto 0) := (others => '0');
    signal op : std_logic_vector(1 downto 0) := (others => '0');
    signal s  : std_logic_vector(7 downto 0);
    signal c  : std_logic;
begin

    dut : entity work.shifter_8
        port map (A => a, OP => op, S => s, C => c);

    stim : process
        constant EXPECTED_VECTORS : natural := 4 * 256;
        variable vectors : natural := 0;
        variable errors  : natural := 0;
        variable ref_s   : natural;
        variable ref_c   : std_logic;
    begin
        for iop in 0 to 3 loop
            for ia in 0 to 255 loop
                a  <= to_slv(ia, 8);
                op <= to_slv(iop, 2);
                wait for 1 ns;

                ref_s   := ref_shift(ia, iop);
                ref_c   := ref_shift_carry(ia, iop);
                vectors := vectors + 1;
                if s /= to_slv(ref_s, 8) or c /= ref_c then
                    tb_error(errors, "OP=" & integer'image(iop) & " A=" & hex(ia, 2) &
                             " got S=" & hex(s) & " C=" & sl_char(c) &
                             " exp S=" & hex(ref_s, 2) & " C=" & sl_char(ref_c));
                end if;
            end loop;
        end loop;

        tb_summary("tb_shifter_8", vectors, EXPECTED_VECTORS, 0, errors);
        wait;
    end process stim;

end architecture sim;
