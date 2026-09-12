
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity shifter_8 is
    port (
        A   : in  std_logic_vector(7 downto 0); -- Donnée à décaler (8 bits)
        OP  : in  std_logic_vector(1 downto 0); -- Commande de décalage
        S   : out std_logic_vector(7 downto 0); -- Résultat décalé
        C   : out std_logic                     -- Retenue sortante (Carry) correspondant au bit éjecté
    );
end shifter_8;

architecture comportementale of shifter_8 is
begin
    process(A, OP)
    begin
        case OP is
            when "00" =>              -- SHL : décalage logique vers la gauche (insertion d'un '0')
                S <= A(6 downto 0) & '0';
                C <= A(7);            -- Sortie du bit de poids fort
            when "01" =>              -- SHR : décalage logique vers la droite (insertion d'un '0')
                S <= '0' & A(7 downto 1);
                C <= A(0);            -- Sortie du bit de poids faible
            when "10" =>              -- SAR : décalage arithmétique vers la droite (extension de signe)
                S <= A(7) & A(7 downto 1);
                C <= A(0);            -- Sortie du bit de poids faible
            when others =>            -- ROL : rotation vers la gauche (le MSB revient en LSB)
                S <= A(6 downto 0) & A(7);
                C <= A(7);            -- Sortie répliquée dans la retenue
        end case;
    end process;
end comportementale;