
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mult_shift_add is
    port (
        clk   : in  std_logic;                    -- Horloge systeme
        reset : in  std_logic;                    -- Reset asynchrone (actif a l'etat bas)
        start : in  std_logic;                    -- Signal de demarrage de la multiplication
        A_in  : in  std_logic_vector(7 downto 0); -- Multiplicande (8 bits)
        B_in  : in  std_logic_vector(7 downto 0); -- Multiplicateur (8 bits)
        R_out : out std_logic_vector(15 downto 0);-- Resultat de la multiplication (16 bits)
        done  : out std_logic                     -- Signal de fin indiquant que le resultat est pret
    );
end mult_shift_add;

architecture comportementale of mult_shift_add is

    type etat_type is (IDLE, CALC, WAIT_LOW); 
    -- IDLE : Attente du signal start
    -- CALC : Boucle de calcul (Addition/Decalage) sur 8 cycles
    -- WAIT_LOW : Attente que le signal start redescende a '0'
    signal etat  : etat_type;

    -- Registres internes pour les calculs
    signal A_reg : std_logic_vector(7 downto 0)  := (others => '0'); -- Memorisation de l'operande A
    signal B_reg : std_logic_vector(7 downto 0)  := (others => '0'); -- Memorisation et decalage de l'operande B
    signal R_reg : std_logic_vector(15 downto 0) := (others => '0'); -- Accumulateur du resultat
    signal i_reg : integer range 0 to 8 := 0; -- Compteur d'iterations

    -- Signaux pour l'additionneur interne
    signal add_A : std_logic_vector(7 downto 0);
    signal add_B : std_logic_vector(7 downto 0);
    signal add_S : std_logic_vector(7 downto 0);
    signal C     : std_logic_vector(8 downto 0);

    signal concat17_comb : std_logic_vector(16 downto 0);

begin

    R_out <= R_reg;

    -- Routage des entrees de l'additionneur
    add_A <= R_reg(15 downto 8);
    add_B <= A_reg when B_reg(0) = '1' else (others => '0');

    -- Additionneur 8 bits 
    process(add_A, add_B)
        variable c_var : std_logic;
    begin
        c_var := '0'; -- Retenue entrante
        for i in 0 to 7 loop
            add_S(i) <= add_A(i) xor add_B(i) xor c_var;
            c_var    := (add_A(i) and add_B(i)) or (c_var and (add_A(i) xor add_B(i)));
        end loop;
        C(8) <= c_var; -- Retenue sortante finale
    end process;

    -- Concatenation de la nouvelle somme 
    concat17_comb <= C(8) & add_S & R_reg(7 downto 0);

    process(clk, reset)
    begin
        if reset = '0' then
            -- Reinitialisation de la FSM et des registres
            etat  <= IDLE;
            A_reg <= (others => '0');
            B_reg <= (others => '0');
            R_reg <= (others => '0');
            i_reg <= 0;
            done  <= '0';

        elsif rising_edge(clk) then
            case etat is

                when IDLE =>
                    done <= '0';          
                    if start = '1' then
                        -- Chargement des operandes et debut du calcul
                        A_reg <= A_in;
                        B_reg <= B_in;
                        R_reg <= (others => '0');
                        i_reg <= 0;
                        etat  <= CALC;
                    end if;

                when CALC =>
                    
                    -- Decalage logique a droite du resultat combinatoire
                    R_reg <= concat17_comb(16 downto 1);
                    
                    -- Mise a jour (decalage) de l'operande B pour l'iteration suivante
                    B_reg <= '0' & B_reg(7 downto 1);
                    
                    -- Verification de la condition de fin 
                    if i_reg = 7 then
                        done <= '1';      -- Signalement que le calcul est termine
                        etat <= WAIT_LOW; -- Passage a l'etat d'attente
                    else
                        i_reg <= i_reg + 1;
                    end if;

                when WAIT_LOW =>
                    if start = '0' then
                        done <= '0';
                        etat <= IDLE;
                    end if;

            end case;
        end if;
    end process;

end comportementale;