
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity addsub_8 is
    port (
        A   : in  std_logic_vector(7 downto 0); -- Premier operande d'entree (8 bits)
        B   : in  std_logic_vector(7 downto 0); -- Second operande d'entree (8 bits)
        sub : in  std_logic;                    -- Commande : 0 = Addition, 1 = Soustraction
        S   : out std_logic_vector(7 downto 0); -- Resultat de l'operation
        C   : out std_logic;                    -- Retenue (Carry) ou indicateur de non-emprunt
        V   : out std_logic                     -- Indicateur de debordement (Overflow) en signe
    );
end addsub_8;

architecture comportementale of addsub_8 is

begin

    process(A, B, sub)
        variable C_var : std_logic_vector(8 downto 0);
        variable B_eff : std_logic_vector(7 downto 0);
    begin
        -- La retenue initiale vaut 1 pour une soustraction (complement a 2), 0 pour une addition
        C_var(0) := sub;
        
        for i in 0 to 7 loop
            -- Inversion bit a bit de B si soustraction (B_eff = B xor sub)
            B_eff(i) := B(i) xor sub;
            
            -- Equations de la somme (S) et de la retenue (C) pour un additionneur complet
            S(i) <= A(i) xor B_eff(i) xor C_var(i);
            C_var(i+1) := (A(i) and B_eff(i)) or (C_var(i) and (A(i) xor B_eff(i)));
        end loop;
        
        -- Retenue finale
        C <= C_var(8);
        
        -- Debordement signe (V) : detecte par le XOR entre les deux dernieres retenues
        V <= C_var(8) xor C_var(7);
    end process;

end comportementale;