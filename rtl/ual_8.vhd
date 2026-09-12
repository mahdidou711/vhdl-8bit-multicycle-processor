
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ual_8 is
    port (
        clk    : in  std_logic;                    -- Horloge systeme
        reset  : in  std_logic;                    -- Reset asynchrone (actif bas)
        start  : in  std_logic;                    -- Lance la commande de calcul
        A      : in  std_logic_vector(7 downto 0); -- Premier operande
        B      : in  std_logic_vector(7 downto 0); -- Second operande
        OP     : in  std_logic_vector(3 downto 0); -- Code operation (16 choix possibles)
        RESULT : out std_logic_vector(7 downto 0); -- Resultat principal
        Z      : out std_logic;                    -- Flag : Zero (Z=1 si RESULT=0)
        N      : out std_logic;                    -- Flag : Negatif (N=1 si MSB(RESULT)=1)
        C      : out std_logic;                    -- Flag : Retenue sortante (Carry)
        V      : out std_logic;                    -- Flag : Debordement (Overflow)
        done   : out std_logic                     -- Interruption de fin de traitement
    );
end ual_8;

architecture comportementale of ual_8 is

    -- Composants
    component addsub_8
        port (
            A   : in  std_logic_vector(7 downto 0);
            B   : in  std_logic_vector(7 downto 0);
            sub : in  std_logic;
            S   : out std_logic_vector(7 downto 0);
            C   : out std_logic;
            V   : out std_logic
        );
    end component;

    component shifter_8
        port (
            A  : in  std_logic_vector(7 downto 0);
            OP : in  std_logic_vector(1 downto 0);
            S  : out std_logic_vector(7 downto 0);
            C  : out std_logic
        );
    end component;

    component logic_8
        port (
            A  : in  std_logic_vector(7 downto 0);
            B  : in  std_logic_vector(7 downto 0);
            OP : in  std_logic_vector(1 downto 0);
            S  : out std_logic_vector(7 downto 0)
        );
    end component;

    component mult_shift_add
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            start : in  std_logic;
            A_in  : in  std_logic_vector(7 downto 0);
            B_in  : in  std_logic_vector(7 downto 0);
            R_out : out std_logic_vector(15 downto 0);
            done  : out std_logic
        );
    end component;

    component sqrt16
        port (
            clk   : in  std_logic;
            reset : in  std_logic;
            start : in  std_logic;
            X_in  : in  std_logic_vector(15 downto 0);
            R_out : out std_logic_vector(7 downto 0);
            done  : out std_logic
        );
    end component;

    -- Signaux internes combinatoires
    signal add_S   : std_logic_vector(7 downto 0);
    signal add_C   : std_logic;
    signal add_V   : std_logic;
    signal sub_S   : std_logic_vector(7 downto 0);
    signal sub_C   : std_logic;
    signal sub_V   : std_logic;
    signal shl_S   : std_logic_vector(7 downto 0);
    signal shl_C   : std_logic;
    signal shr_S   : std_logic_vector(7 downto 0);
    signal shr_C   : std_logic;
    signal sar_S   : std_logic_vector(7 downto 0);
    signal sar_C   : std_logic;
    signal rol_S   : std_logic_vector(7 downto 0);
    signal rol_C   : std_logic;
    signal and_S   : std_logic_vector(7 downto 0);
    signal or_S    : std_logic_vector(7 downto 0);
    signal xor_S   : std_logic_vector(7 downto 0);
    signal not_S   : std_logic_vector(7 downto 0);

    -- Signaux sequentiels
    signal mult_R  : std_logic_vector(15 downto 0);
    signal mult_done : std_logic;
    signal mult_start : std_logic;

    signal sqrt_R  : std_logic_vector(7 downto 0);
    signal sqrt_done : std_logic;
    signal sqrt_start : std_logic;
    signal sqrt_X  : std_logic_vector(15 downto 0);

    -- FSM
    type etat_type is (IDLE, RUN_COMB, RUN_MUL, RUN_SQRT, DONE_STATE);
    signal etat : etat_type;

    -- Registres de sortie
    signal res_reg : std_logic_vector(7 downto 0);
    signal Z_reg   : std_logic;
    signal N_reg   : std_logic;
    signal C_reg   : std_logic;
    signal V_reg   : std_logic;

begin

    -- Instanciation addsub (ADD)
    U_ADD : addsub_8
        port map (A => A, B => B, sub => '0',
                  S => add_S, C => add_C, V => add_V);

    -- Instanciation addsub (SUB)
    U_SUB : addsub_8
        port map (A => A, B => B, sub => '1',
                  S => sub_S, C => sub_C, V => sub_V);

    -- Instanciation shifter (SHL)
    U_SHL : shifter_8
        port map (A => A, OP => "00", S => shl_S, C => shl_C);

    -- Instanciation shifter (SHR)
    U_SHR : shifter_8
        port map (A => A, OP => "01", S => shr_S, C => shr_C);

    -- Instanciation shifter (SAR)
    U_SAR : shifter_8
        port map (A => A, OP => "10", S => sar_S, C => sar_C);

    -- Instanciation shifter (ROL)
    U_ROL : shifter_8
        port map (A => A, OP => "11", S => rol_S, C => rol_C);

    -- Instanciation logic (AND)
    U_AND : logic_8
        port map (A => A, B => B, OP => "00", S => and_S);

    -- Instanciation logic (OR)
    U_OR : logic_8
        port map (A => A, B => B, OP => "01", S => or_S);

    -- Instanciation logic (XOR)
    U_XOR : logic_8
        port map (A => A, B => B, OP => "10", S => xor_S);

    -- Instanciation logic (NOT)
    U_NOT : logic_8
        port map (A => A, B => B, OP => "11", S => not_S);

    -- Instanciation multiplieur
    mult_start <= start when (OP = "1010" and etat = IDLE) else '0';
    U_MULT : mult_shift_add
        port map (
            clk   => clk,
            reset => reset,
            start => mult_start,
            A_in  => A,
            B_in  => B,
            R_out => mult_R,
            done  => mult_done
        );

    -- Instanciation sqrt
    sqrt_X    <= x"00" & A;
    sqrt_start <= start when (OP = "1011" and etat = IDLE) else '0';
    U_SQRT : sqrt16
        port map (
            clk   => clk,
            reset => reset,
            start => sqrt_start,
            X_in  => sqrt_X,
            R_out => sqrt_R,
            done  => sqrt_done
        );

    -- Sorties
    RESULT <= res_reg;
    Z      <= Z_reg;
    N      <= N_reg;
    C      <= C_reg;
    V      <= V_reg;

    -- FSM de l'UAL gerant les delais 
    process(clk, reset)
    begin
        if reset = '0' then
            etat    <= IDLE;
            done    <= '0';
            res_reg <= (others => '0');
            Z_reg   <= '0';
            N_reg   <= '0';
            C_reg   <= '0';
            V_reg   <= '0';

        elsif rising_edge(clk) then
            case etat is

                when IDLE =>
                    -- Etat de repos en attente de commande
                    done <= '0';
                    if start = '1' then
                        case OP is
                            when "1010" => etat <= RUN_MUL;   -- Mode long : Multiplication (8 cycles)
                            when "1011" => etat <= RUN_SQRT;  -- Mode long : Racine Carree (n cycles)
                            when others => etat <= RUN_COMB;  -- Mode direct : operations combinatoires instantanees
                        end case;
                    end if;

                when RUN_COMB =>
                    -- Selection en mode immediat (combinatoire)
                    case OP is
                        when "0000" => -- OP_ADD
                            res_reg <= add_S;
                            C_reg   <= add_C; V_reg <= add_V;
                        when "0001" => -- OP_SUB
                            res_reg <= sub_S;
                            -- Inversion de sub_C selon convention "not Borrow" vs Carry
                            C_reg   <= not sub_C; V_reg <= sub_V;
                        when "0010" => -- OP_AND
                            res_reg <= and_S;
                            C_reg <= '0'; V_reg <= '0';
                        when "0011" => -- OP_OR
                            res_reg <= or_S;
                            C_reg <= '0'; V_reg <= '0';
                        when "0100" => -- OP_XOR
                            res_reg <= xor_S;
                            C_reg <= '0'; V_reg <= '0';
                        when "0101" => -- OP_NOT
                            res_reg <= not_S;
                            C_reg <= '0'; V_reg <= '0';
                        when "0110" => -- OP_SHL (Shift Left)
                            res_reg <= shl_S;
                            C_reg <= shl_C; V_reg <= '0';
                        when "0111" => -- OP_SHR (Shift Right)
                            res_reg <= shr_S;
                            C_reg <= shr_C; V_reg <= '0';
                        when "1000" => -- OP_SAR (Shift Arithmetic Right)
                            res_reg <= sar_S;
                            C_reg <= sar_C; V_reg <= '0';
                        when "1001" => -- OP_ROL (Rotate Left)
                            res_reg <= rol_S;
                            C_reg <= rol_C; V_reg <= '0';
                        when others => -- NOP ou Operation non definie
                            res_reg <= (others => '0');
                            C_reg <= '0'; V_reg <= '0';
                    end case;
                    etat <= DONE_STATE;

                when RUN_MUL =>
                    -- Attente de la fin de multiplication issue de U_MULT
                    if mult_done = '1' then
                        -- Limitation du resultat sur 8 bits pour l'UAL
                        res_reg <= mult_R(7 downto 0);
                        C_reg   <= '0';
                        V_reg   <= '0';
                        etat    <= DONE_STATE;
                    end if;

                when RUN_SQRT =>
                    -- Attente de la fin de racine carree issue de U_SQRT
                    if sqrt_done = '1' then
                        res_reg <= sqrt_R;
                        C_reg   <= '0';
                        V_reg   <= '0';
                        etat    <= DONE_STATE;
                    end if;

                when DONE_STATE =>
                    -- Mise a jour globale des drapeaux negatif (N) et zero (Z) avant rebouclage
                    N_reg <= res_reg(7);
                    if res_reg = x"00" then
                        Z_reg <= '1';
                    else
                        Z_reg <= '0';
                    end if;
                    done  <= '1'; -- Signal de fin valide pour l'exterieur
                    if start = '0' then
                        done <= '0';
                        etat <= IDLE;
                    end if;

            end case;
        end if;
    end process;

end comportementale;