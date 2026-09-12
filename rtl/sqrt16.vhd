
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity sqrt16 is
    port (
        clk   : in  std_logic;                     -- Horloge de synchronisation globale
        reset : in  std_logic;                     -- Signal de réinitialisation (actif à 0 bas)
        start : in  std_logic;                     -- Impulsion de démarrage du calcul
        X_in  : in  std_logic_vector(15 downto 0); -- Valeur d'entrée (16 bits)
        R_out : out std_logic_vector(7 downto 0);  -- Résultat de la racine carrée (8 bits max car sqrt(65535)=255)
        done  : out std_logic                      -- Indicateur de finalisation des itérations
    );
end sqrt16;

architecture comportementale of sqrt16 is

    -- États du processus itératif
    type etat_type is (IDLE, COMPUTE, FINISH, WAIT_LOW);
    signal etat : etat_type;

    -- Signaux internes de travail 
    signal X_reg : std_logic_vector(16 downto 0); -- Vecteur X 
    signal Z_reg : std_logic_vector(16 downto 0); -- Registre cible contenant progressivement l'approximation du résultat 
    signal V_reg : std_logic_vector(16 downto 0); -- Variable de test 
    signal cpt   : integer range 0 to 7;  -- Compteur (8 itérations)
    signal R_reg : std_logic_vector(7 downto 0); -- Stockage du résultat 

    -- Signaux combinatoires 

    signal ZpV_s    : std_logic_vector(16 downto 0);
    signal c_ZpV    : std_logic_vector(17 downto 0);
    
    signal XmZpV_s  : std_logic_vector(16 downto 0);
    signal c_XmZpV  : std_logic_vector(17 downto 0);
    
    signal ZpVpV_s  : std_logic_vector(16 downto 0);
    signal c_ZpVpV  : std_logic_vector(17 downto 0);
    
    signal ZpVm_V_s : std_logic_vector(16 downto 0);
    signal c_ZpVm_V : std_logic_vector(17 downto 0);

begin

    -- Affectation continue du port de sortie vers le registre de mémorisation
    R_out <= R_reg;

    -- Additions et Soustractions avec des boucles for dans un process combinatoire (avec variables pour la retenue)
    process(X_reg, Z_reg, V_reg)
        variable v_ZpV_s    : std_logic_vector(16 downto 0);
        variable v_c_ZpV    : std_logic;
        
        variable v_XmZpV_s  : std_logic_vector(16 downto 0);
        variable v_c_XmZpV  : std_logic;
        
        variable v_ZpVpV_s  : std_logic_vector(16 downto 0);
        variable v_c_ZpVpV  : std_logic;
        
        variable v_ZpVm_V_s : std_logic_vector(16 downto 0);
        variable v_c_ZpVm_V : std_logic;
    begin
        v_c_ZpV    := '0';
        v_c_XmZpV  := '1'; -- Soustraction (+1)
        v_c_ZpVpV  := '0';
        v_c_ZpVm_V := '1'; -- Soustraction (+1)

        for i in 0 to 16 loop
            -- 1) Z_tmp = Z_reg + V_reg
            v_ZpV_s(i) := Z_reg(i) xor V_reg(i) xor v_c_ZpV;
            v_c_ZpV    := (Z_reg(i) and V_reg(i)) or (v_c_ZpV and (Z_reg(i) xor V_reg(i)));

            -- 2) X_reg - Z_tmp (ZpV_s). X_reg + (not ZpV_s) + 1
            v_XmZpV_s(i) := X_reg(i) xor (not v_ZpV_s(i)) xor v_c_XmZpV;
            v_c_XmZpV    := (X_reg(i) and (not v_ZpV_s(i))) or (v_c_XmZpV and (X_reg(i) xor (not v_ZpV_s(i))));

            -- 3) Z_tmp (ZpV_s) + V_reg
            v_ZpVpV_s(i) := v_ZpV_s(i) xor V_reg(i) xor v_c_ZpVpV;
            v_c_ZpVpV    := (v_ZpV_s(i) and V_reg(i)) or (v_c_ZpVpV and (v_ZpV_s(i) xor V_reg(i)));

            -- 4) Z_tmp (ZpV_s) - V_reg. ZpV_s + (not V_reg) + 1
            v_ZpVm_V_s(i) := v_ZpV_s(i) xor (not V_reg(i)) xor v_c_ZpVm_V;
            v_c_ZpVm_V    := (v_ZpV_s(i) and (not V_reg(i))) or (v_c_ZpVm_V and (v_ZpV_s(i) xor (not V_reg(i))));
        end loop;

        -- Affectation aux signaux combinatoires
        ZpV_s    <= v_ZpV_s;
        c_ZpV(17) <= v_c_ZpV;
        
        XmZpV_s  <= v_XmZpV_s;
        c_XmZpV(17) <= v_c_XmZpV;
        
        ZpVpV_s  <= v_ZpVpV_s;
        c_ZpVpV(17) <= v_c_ZpVpV;
        
        ZpVm_V_s <= v_ZpVm_V_s;
        c_ZpVm_V(17) <= v_c_ZpVm_V;
    end process;

    -- Séquenceur principal du bloc matériel
    process(clk, reset)
    begin
        if reset = '0' then
            -- Nettoyage global de la machine et des registres
            etat  <= IDLE;
            done  <= '0';
            R_reg <= (others => '0');
            X_reg <= (others => '0');
            Z_reg <= (others => '0');
            V_reg <= (others => '0');
            cpt   <= 0;

        elsif rising_edge(clk) then
            case etat is

                when IDLE =>
                    -- Attente de la commande de la part de l'UAL (via Signal start)
                    done <= '0';
                    if start = '1' then
                        -- Initialisation des variables pour la racine (Méthode de la soustraction des séries impaires ou assimilés)
                        X_reg <= '0' & X_in;                     -- Chargement de l'entrée (17 bits)
                        V_reg <= "00100000000000000";            -- Test du bit de poids le plus puissant : 16384 = 2^14
                        Z_reg <= (others => '0');                -- Init à zéro
                        cpt   <= 0;
                        etat  <= COMPUTE;                        -- Passe à la FSM de calcul
                    end if;

                when COMPUTE =>
                    -- Calcul itératif principal (8 boucles)
                    
                    -- Si X_reg >= ZpV_s (pas d'emprunt sur la retenue globale)
                    if c_XmZpV(17) = '1' then
                        -- On soustrait et on met à jour Z pour accumuler
                        X_reg <= XmZpV_s;
                        -- Z <= (Z+V+V) >> 1
                        Z_reg <= '0' & ZpVpV_s(16 downto 1);
                    else
                        -- Sinon, on décale Z sans accumulation positive
                        -- Z <= (Z+V-V) >> 1
                        Z_reg <= '0' & ZpVm_V_s(16 downto 1);
                    end if;
                    
                    -- Le bit de test glissant V est divisé par 4 à chaque itération (décalage >> 2)
                    V_reg <= "00" & V_reg(16 downto 2);
                    
                    if cpt = 7 then
                        etat <= FINISH; -- Vérifie qu'on a bien fait nos 8 passages
                    else
                        cpt <= cpt + 1;
                    end if;

                when FINISH =>
                    -- Validation du résultat dans le registre de la sortie (on isole les 8 bits du registre final Z_reg)
                    R_reg <= std_logic_vector(Z_reg(7 downto 0));
                    done  <= '1';     -- Préviens l'UAL
                    etat  <= WAIT_LOW;

                when WAIT_LOW =>
                    -- Sécurité : attend la relève du signal START par le séquenceur parent
                    if start = '0' then
                        done <= '0';
                        etat <= IDLE;
                    end if;

            end case;
        end if;
    end process;

end comportementale;