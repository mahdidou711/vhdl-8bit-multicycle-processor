
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity logic_8 is
    port (
        A  : in  std_logic_vector(7 downto 0); -- Premier opérande 8 bits
        B  : in  std_logic_vector(7 downto 0); -- Deuxième opérande 8 bits
        OP : in  std_logic_vector(1 downto 0); -- Sélecteur d'opération logique
        S  : out std_logic_vector(7 downto 0)  -- Résultat
    );
end logic_8;

architecture comportementale of logic_8 is
begin
    process(A, B, OP)
    begin
        case OP is
            when "00"   => S <= A and B; -- Opération ET
            when "01"   => S <= A or  B; -- Opération OU
            when "10"   => S <= A xor B; -- Opération OU Exclusif
            when others => S <= not A;   -- Opération NON 
        end case;
    end process;
end comportementale;