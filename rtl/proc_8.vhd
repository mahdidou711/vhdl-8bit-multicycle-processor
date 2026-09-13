
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;  

entity proc_8 is
    port (
        clk   : in  std_logic;                    -- Horloge systeme (CLOCK_50 sur DE1)
        reset : in  std_logic;                    -- Reset asynchrone actif bas (KEY(0) sur DE1)
        -- Ports de sortie ajoutes pour l'observation sur carte
        R_out : out std_logic_vector(7 downto 0); -- Registre resultat -> LEDR(7:0)
        Z_out : out std_logic;                    -- Flag Zero        -> LEDG(0)
        N_out : out std_logic;                    -- Flag Negatif     -> LEDG(1)
        C_out : out std_logic;                    -- Flag Carry       -> LEDG(2)
        V_out : out std_logic                     -- Flag Overflow    -> LEDG(3)
    );
end proc_8;

architecture comportementale of proc_8 is

    
    -- Declaration du composant UAL
    component ual_8
        port (
            clk    : in  std_logic;                    -- Horloge partagee avec le processeur
            reset  : in  std_logic;                    -- Reset partage avec le processeur
            start  : in  std_logic;                    -- Lancement d'une operation UAL
            A      : in  std_logic_vector(7 downto 0); -- Operande A
            B      : in  std_logic_vector(7 downto 0); -- Operande B
            OP     : in  std_logic_vector(3 downto 0); -- Code operation (4 bits)
            RESULT : out std_logic_vector(7 downto 0); -- Resultat de l'operation
            Z      : out std_logic;                    -- Flag Zero
            N      : out std_logic;                    -- Flag Negatif
            C      : out std_logic;                    -- Flag Carry
            V      : out std_logic;                    -- Flag Overflow
            done   : out std_logic                     -- Signal de fin de calcul
        );
    end component;

    ------------
    -- ROM de programme : 16 mots de 8 bits
    -- Encodage : LOAD_A=0x10, LOAD_B=0x11, HALT=0xFF
    -- Opcodes UAL : 0x00..0x0B (4 bits de poids faible)
    ------------
    type rom_type is array(0 to 15) of std_logic_vector(7 downto 0);
    constant ROM : rom_type := (
        0  => x"10",  -- LOAD_A  : charge l'immediat suivant dans A
        1  => x"19",  -- Immediat : valeur 25 (0x19)
        2  => x"11",  -- LOAD_B  : charge l'immediat suivant dans B
        3  => x"07",  -- Immediat : valeur 7 (0x07)
        4  => x"00",  -- ADD     : R <- A + B
        5  => x"01",  -- SUB     : R <- A - B
        6  => x"02",  -- AND     : R <- A AND B
        7  => x"03",  -- OR      : R <- A OR B
        8  => x"04",  -- XOR     : R <- A XOR B
        9  => x"06",  -- SHL     : R <- A decale gauche 1 bit
        10 => x"07",  -- SHR     : R <- A decale droit logique 1 bit
        11 => x"08",  -- SAR     : R <- A decale droit arithmetique 1 bit
        12 => x"09",  -- ROL     : R <- rotation gauche 1 bit
        13 => x"0A",  -- MUL     : R <- (A x B)[7:0]
        14 => x"0B",  -- SQRT    : R <- racine carree entiere de A
        15 => x"FF"   -- HALT    : arret du processeur
    );

    -- Registres internes du processeur
    signal PC  : integer range 0 to 15 := 0; -- Compteur de programme (adresse ROM)
    signal IR  : std_logic_vector(7 downto 0) := (others => '0'); -- Registre instruction courant
    signal A   : std_logic_vector(7 downto 0) := (others => '0'); -- Registre operande A
    signal B   : std_logic_vector(7 downto 0) := (others => '0'); -- Registre operande B
    signal R   : std_logic_vector(7 downto 0) := (others => '0'); -- Registre resultat

    -- Drapeaux de statut (mis a jour apres chaque operation UAL)
    signal Z   : std_logic := '0'; -- Zero    : R = 0x00
    signal N   : std_logic := '0'; -- Negatif : R(7) = 1
    signal C   : std_logic := '0'; -- Carry   : emprunt ou bit ejecte
    signal V   : std_logic := '0'; -- Overflow : debordement signe

     
    -- Signaux d'interface vers l'UAL
    signal ual_start  : std_logic := '0';                    -- Declenchement d'une operation UAL
    signal ual_op     : std_logic_vector(3 downto 0) := (others => '0'); -- Opcode transmis a l'UAL
    signal ual_result : std_logic_vector(7 downto 0);        -- Resultat retourne par l'UAL
    signal ual_Z      : std_logic;                           -- Flag Zero retourne par l'UAL
    signal ual_N      : std_logic;                           -- Flag Negatif retourne par l'UAL
    signal ual_C      : std_logic;                           -- Flag Carry retourne par l'UAL
    signal ual_V      : std_logic;                           -- Flag Overflow retourne par l'UAL
    signal ual_done   : std_logic;                           -- '1' quand l'UAL a termine son calcul

    -- FSM de controle : 7 etats
    type etat_type is (FETCH, DECODE, LOAD_IMM, WRITEBACK,
                       WAIT_UAL, CAPTURE, HALT);
    signal etat : etat_type; -- Etat courant de la machine de controle

begin

    -- Cablage des sorties observables vers les registres internes
    R_out <= R; -- Resultat visible sur LEDR(7:0)
    Z_out <= Z; -- Flag Zero visible sur LEDG(0)
    N_out <= N; -- Flag Negatif visible sur LEDG(1)
    C_out <= C; -- Flag Carry visible sur LEDG(2)
    V_out <= V; -- Flag Overflow visible sur LEDG(3)

    -- Instanciation de l'UAL
    U_UAL : ual_8
        port map (
            clk    => clk,        -- Horloge commune
            reset  => reset,      -- Reset commun
            start  => ual_start,  -- Controle par la FSM
            A      => A,          -- Operande A du registre interne
            B      => B,          -- Operande B du registre interne
            OP     => ual_op,     -- Opcode charge depuis IR par la FSM
            RESULT => ual_result, -- Resultat capture dans CAPTURE
            Z      => ual_Z,      -- Flag capture dans CAPTURE
            N      => ual_N,      -- Flag capture dans CAPTURE
            C      => ual_C,      -- Flag capture dans CAPTURE
            V      => ual_V,      -- Flag capture dans CAPTURE
            done   => ual_done    -- Teste dans WAIT_UAL
        );

    -- Process principal : FSM de controle synchrone
    process(clk, reset)
    begin

        if reset = '0' then
            -- Initialisation de tous les registres au reset
            PC        <= 0;               -- PC pointe sur l'instruction 0
            IR        <= (others => '0'); -- Pas d'instruction en cours
            A         <= (others => '0'); -- Operande A nul
            B         <= (others => '0'); -- Operande B nul
            R         <= (others => '0'); -- Resultat nul
            Z         <= '0';             -- Flag Zero inactif
            N         <= '0';             -- Flag Negatif inactif
            C         <= '0';             -- Flag Carry inactif
            V         <= '0';             -- Flag Overflow inactif
            ual_start <= '0';             -- UAL non declenchee
            ual_op    <= (others => '0'); -- Opcode nul
            etat      <= FETCH;           -- Demarrage en phase d'extraction

        elsif rising_edge(clk) then

            case etat is
                -- FETCH 
                
                when FETCH =>
                    IR   <= ROM(PC); -- Lire l'instruction a l'adresse PC
                    PC   <= (PC + 1) mod 16;     -- Incrementer PC vers l'instruction suivante
                    etat <= DECODE;              -- Passer au decodage

                -- DECODE 
                
                when DECODE =>
                    if IR = x"FF" then           -- Instruction HALT detectee
                        etat <= HALT;
                    elsif IR = x"10" or IR = x"11" then -- LOAD_A ou LOAD_B detecte
                        etat <= LOAD_IMM;
                    else                         -- Opcode UAL (0x00..0x0B)
                        ual_op    <= IR(3 downto 0); -- Les 4 bits bas = opcode UAL
                        ual_start <= '1';            -- Declencher l'UAL
                        etat      <= WAIT_UAL;       -- Attendre la fin du calcul
                    end if;

                
                -- LOAD_IMM 
                
                when LOAD_IMM =>
                    if IR = x"10" then
                        A <= ROM(PC); -- Charger immediat dans A
                    else
                        B <= ROM(PC); -- Charger immediat dans B
                    end if;
                    PC   <= (PC + 1) mod 16; -- Avancer PC apres l'immediat
                    etat <= FETCH;  -- Reprendre le cycle fetch

                
                -- WAIT_UAL : attente de fin de calcul UAL
                
                when WAIT_UAL =>
                    if ual_done = '1' then    -- L'UAL a termine son calcul
                        ual_start <= '0';     -- Relacher le signal de declenchement
                        etat      <= CAPTURE; -- Capturer le resultat
                    end if;                   -- Sinon : rester en attente

                
                -- CAPTURE : lecture du resultat et des flags UAL

                when CAPTURE =>
                    R    <= ual_result; -- Stocker le resultat dans R
                    Z    <= ual_Z;      -- Memoriser le flag Zero
                    N    <= ual_N;      -- Memoriser le flag Negatif
                    C    <= ual_C;      -- Memoriser le flag Carry
                    V    <= ual_V;      -- Memoriser le flag Overflow
                    etat <= WRITEBACK;  -- Passer a l'etat de rebouclage

                
                -- WRITEBACK : transition pure vers FETCH
                
                when WRITEBACK =>
                    etat <= FETCH; -- Reprendre le cycle d'instruction suivant

                
                -- HALT : etat terminal
                
                when HALT =>
                    null; -- Aucune action : l'etat reste HALT

            end case;
        end if;
    end process;

end comportementale;