-- Shared reference models and reporting helpers for the self-checking testbenches.
--
-- The reference functions are written with integer arithmetic (sums, products,
-- divisions, range checks) instead of the ripple-carry / bit-slicing structure
-- used by the RTL, so that a structural mistake in the RTL is not reproduced by
-- the oracle. Flag conventions (C/V per opcode) characterize the original RTL.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_pkg is

    -- Opcodes on the 4-bit OP port of ual_8
    constant OP_ADD  : natural := 16#0#;
    constant OP_SUB  : natural := 16#1#;
    constant OP_AND  : natural := 16#2#;
    constant OP_OR   : natural := 16#3#;
    constant OP_XOR  : natural := 16#4#;
    constant OP_NOT  : natural := 16#5#;
    constant OP_SHL  : natural := 16#6#;
    constant OP_SHR  : natural := 16#7#;
    constant OP_SAR  : natural := 16#8#;
    constant OP_ROL  : natural := 16#9#;
    constant OP_MUL  : natural := 16#A#;
    constant OP_SQRT : natural := 16#B#;

    -- Maximum number of detailed mismatch messages printed per testbench
    constant MAX_REPORTS : natural := 10;

    -- Architectural ALU outputs: RESULT and Z/N/C/V
    type alu_ref_t is record
        result : natural range 0 to 255;
        z      : std_logic;
        n      : std_logic;
        c      : std_logic;
        v      : std_logic;
    end record;

    -- Value of RESULT/Z/N/C/V right after an asynchronous reset of ual_8/proc_8
    constant ALU_RESET_STATE : alu_ref_t := (result => 0, z => '0', n => '0', c => '0', v => '0');

    function to_sl(b : boolean) return std_logic;
    function wrap8(x : integer) return natural;           -- x mod 256
    function to_s8(x : natural) return integer;           -- 0..255 -> -128..127
    function bit_at(x : natural; i : natural) return natural;
    function signed_overflow(x : integer) return std_logic;

    -- op: 0 AND, 1 OR, 2 XOR, 3 NOT A (encoding of logic_8.OP)
    function ref_logic(a, b : natural; op : natural) return natural;
    -- op: 0 SHL, 1 SHR, 2 SAR, 3 ROL (encoding of shifter_8.OP)
    function ref_shift(a : natural; op : natural) return natural;
    function ref_shift_carry(a : natural; op : natural) return std_logic;

    function ref_isqrt(x : natural) return natural;       -- linear search, small x only
    function is_isqrt(x, r : natural) return boolean;     -- r*r <= x < (r+1)*(r+1)

    function ref_alu(op, a, b : natural) return alu_ref_t;

    -- ual_8 latency: rising edges from the edge sampling start='1' in IDLE (inclusive)
    -- until done='1' is visible. Derivation in tb_ual_8.vhd.
    function alu_latency(op : natural) return positive;

    function flags_str(e : alu_ref_t) return string;      -- "ZNCV" as '0'/'1' characters

    function to_slv(x : natural; width : positive) return std_logic_vector;
    function to_nat(v : std_logic_vector) return integer; -- -1 if v contains a metavalue
    function hex(x : natural; digits : positive) return string;
    function hex(v : std_logic_vector) return string;
    function sl_char(s : std_logic) return character;

    -- Counts a non-fatal mismatch and prints at most MAX_REPORTS messages
    procedure tb_error(variable errors : inout natural; msg : in string);

    -- Final verdict line parsed by sim/ghdl/run_tests.sh
    procedure tb_summary(name : in string;
                         vectors : in natural; expected_vectors : in natural;
                         directed : in natural; errors : in natural);

end package tb_pkg;

package body tb_pkg is

    function to_sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    function wrap8(x : integer) return natural is
    begin
        return x mod 256;  -- VHDL "mod" takes the sign of the divisor: always 0..255
    end function;

    function to_s8(x : natural) return integer is
    begin
        if x >= 128 then
            return x - 256;
        else
            return x;
        end if;
    end function;

    function bit_at(x : natural; i : natural) return natural is
    begin
        return (x / (2 ** i)) mod 2;
    end function;

    function signed_overflow(x : integer) return std_logic is
    begin
        return to_sl(x > 127 or x < -128);
    end function;

    function ref_logic(a, b : natural; op : natural) return natural is
        variable r     : natural := 0;
        variable ba    : natural;
        variable bb    : natural;
        variable bit_r : natural;
    begin
        if op = 3 then
            return 255 - a;  -- one's complement of an 8-bit value
        end if;
        for i in 7 downto 0 loop
            ba := bit_at(a, i);
            bb := bit_at(b, i);
            case op is
                when 0      => bit_r := ba * bb;             -- AND
                when 1      => bit_r := ba + bb - ba * bb;   -- OR
                when others => bit_r := (ba + bb) mod 2;     -- XOR
            end case;
            r := 2 * r + bit_r;
        end loop;
        return r;
    end function;

    function ref_shift(a : natural; op : natural) return natural is
        variable s : integer;
    begin
        case op is
            when 0 =>                              -- SHL: multiply by 2, drop bit 8
                return (2 * a) mod 256;
            when 1 =>                              -- SHR: unsigned divide by 2
                return a / 2;
            when 2 =>                              -- SAR: floor(signed / 2)
                s := to_s8(a);
                return wrap8((s - (s mod 2)) / 2);
            when others =>                         -- ROL: bit 7 re-enters at bit 0
                return (2 * a) mod 256 + a / 128;
        end case;
    end function;

    function ref_shift_carry(a : natural; op : natural) return std_logic is
    begin
        case op is
            when 1 | 2  => return to_sl(a mod 2 = 1);  -- SHR/SAR: bit shifted out on the right
            when others => return to_sl(a >= 128);     -- SHL/ROL: bit 7
        end case;
    end function;

    function ref_isqrt(x : natural) return natural is
        variable r : natural := 0;
    begin
        while (r + 1) * (r + 1) <= x loop
            r := r + 1;
        end loop;
        return r;
    end function;

    function is_isqrt(x, r : natural) return boolean is
    begin
        return r * r <= x and x < (r + 1) * (r + 1);
    end function;

    function ref_alu(op, a, b : natural) return alu_ref_t is
        variable e : alu_ref_t;
    begin
        e.result := 0;
        e.c      := '0';
        e.v      := '0';
        case op is
            when OP_ADD =>
                e.result := wrap8(a + b);
                e.c      := to_sl(a + b > 255);
                e.v      := signed_overflow(to_s8(a) + to_s8(b));
            when OP_SUB =>
                e.result := wrap8(a - b);
                e.c      := to_sl(a < b);  -- ual_8 inverts the adder carry: C = borrow
                e.v      := signed_overflow(to_s8(a) - to_s8(b));
            when OP_AND => e.result := ref_logic(a, b, 0);
            when OP_OR  => e.result := ref_logic(a, b, 1);
            when OP_XOR => e.result := ref_logic(a, b, 2);
            when OP_NOT => e.result := ref_logic(a, b, 3);
            when OP_SHL =>
                e.result := ref_shift(a, 0);
                e.c      := ref_shift_carry(a, 0);
            when OP_SHR =>
                e.result := ref_shift(a, 1);
                e.c      := ref_shift_carry(a, 1);
            when OP_SAR =>
                e.result := ref_shift(a, 2);
                e.c      := ref_shift_carry(a, 2);
            when OP_ROL =>
                e.result := ref_shift(a, 3);
                e.c      := ref_shift_carry(a, 3);
            when OP_MUL =>
                e.result := (a * b) mod 256;   -- low byte of the 16-bit product
            when OP_SQRT =>
                e.result := ref_isqrt(a);      -- sqrt of x"00" & A
            when others =>
                e.result := 0;                 -- opcodes C..F
        end case;
        e.z := to_sl(e.result = 0);
        e.n := to_sl(e.result >= 128);
        return e;
    end function;

    function alu_latency(op : natural) return positive is
    begin
        case op is
            when OP_MUL  => return 11;
            when OP_SQRT => return 12;
            when others  => return 3;
        end case;
    end function;

    function sl_char(s : std_logic) return character is
    begin
        case s is
            when '0'    => return '0';
            when '1'    => return '1';
            when others => return 'X';
        end case;
    end function;

    function flags_str(e : alu_ref_t) return string is
        variable s : string(1 to 4);
    begin
        s(1) := sl_char(e.z);
        s(2) := sl_char(e.n);
        s(3) := sl_char(e.c);
        s(4) := sl_char(e.v);
        return s;
    end function;

    function to_slv(x : natural; width : positive) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(x, width));
    end function;

    function to_nat(v : std_logic_vector) return integer is
    begin
        if Is_X(v) then
            return -1;
        end if;
        return to_integer(unsigned(v));
    end function;

    function hex(x : natural; digits : positive) return string is
        constant HEX_CHARS : string(1 to 16) := "0123456789ABCDEF";
        variable s : string(1 to digits);
        variable t : natural := x;
    begin
        for i in digits downto 1 loop
            s(i) := HEX_CHARS(t mod 16 + 1);
            t    := t / 16;
        end loop;
        return s;
    end function;

    function hex(v : std_logic_vector) return string is
        constant DIGITS : positive := (v'length + 3) / 4;
        variable s : string(1 to DIGITS) := (others => 'X');
    begin
        if Is_X(v) then
            return s;
        end if;
        return hex(to_integer(unsigned(v)), DIGITS);
    end function;

    procedure tb_error(variable errors : inout natural; msg : in string) is
    begin
        errors := errors + 1;
        if errors <= MAX_REPORTS then
            report "MISMATCH: " & msg severity error;
        elsif errors = MAX_REPORTS + 1 then
            report "further mismatch messages suppressed" severity error;
        end if;
    end procedure;

    procedure tb_summary(name : in string;
                         vectors : in natural; expected_vectors : in natural;
                         directed : in natural; errors : in natural) is
        constant COUNTS : string := " vectors=" & integer'image(vectors) &
                                    " directed=" & integer'image(directed) &
                                    " errors=" & integer'image(errors);
    begin
        if errors = 0 and vectors = expected_vectors then
            report "TB_RESULT " & name & " PASS" & COUNTS severity note;
        else
            report "TB_RESULT " & name & " FAIL" & COUNTS &
                   " expected_vectors=" & integer'image(expected_vectors) severity failure;
        end if;
    end procedure;

end package body tb_pkg;
