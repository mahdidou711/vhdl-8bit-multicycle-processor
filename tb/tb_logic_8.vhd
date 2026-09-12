-- Exhaustive self-checking testbench for logic_8 (combinational).
--
-- Space: OP in 0..3 x A in 0..255 x B in 0..255 = 262,144 vectors.
-- OP encoding: "00" AND, "01" OR, "10" XOR, "11" NOT A (B ignored).

library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_logic_8 is
end entity tb_logic_8;

architecture sim of tb_logic_8 is
    signal a  : std_logic_vector(7 downto 0) := (others => '0');
    signal b  : std_logic_vector(7 downto 0) := (others => '0');
    signal op : std_logic_vector(1 downto 0) := (others => '0');
    signal s  : std_logic_vector(7 downto 0);
begin

    dut : entity work.logic_8
        port map (A => a, B => b, OP => op, S => s);

    stim : process
        constant EXPECTED_VECTORS : natural := 4 * 256 * 256;
        variable vectors : natural := 0;
        variable errors  : natural := 0;
        variable ref_s   : natural;
    begin
        for iop in 0 to 3 loop
            for ia in 0 to 255 loop
                for ib in 0 to 255 loop
                    a  <= to_slv(ia, 8);
                    b  <= to_slv(ib, 8);
                    op <= to_slv(iop, 2);
                    wait for 1 ns;

                    ref_s   := ref_logic(ia, ib, iop);
                    vectors := vectors + 1;
                    if s /= to_slv(ref_s, 8) then
                        tb_error(errors, "OP=" & integer'image(iop) &
                                 " A=" & hex(ia, 2) & " B=" & hex(ib, 2) &
                                 " got S=" & hex(s) & " exp S=" & hex(ref_s, 2));
                    end if;
                end loop;
            end loop;
        end loop;

        tb_summary("tb_logic_8", vectors, EXPECTED_VECTORS, 0, errors);
        wait;
    end process stim;

end architecture sim;
