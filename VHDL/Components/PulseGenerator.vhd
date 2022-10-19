library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.all;

-- Edge triggered pulse generator
entity PulseGenerator is
    generic (
        IDLE_OUTPUT  : std_logic;        -- Idle output state - pulse state is inverted IDLE_OUTPUT
        PULSE_LENGTH : natural;          -- Length of a pulse in clock cycles
        CLOCK_EDGE   : std_logic := '1'; -- Process clock edge
        TRIGGER_EDGE : std_logic := '1'; -- Default trigger on transition from 0 to 1
        BOTH_EDGES   : std_logic := '0'  -- Generate pulse on both trigger edges
    );
    port (
        clock   : in std_logic;
        trigger : in std_logic; -- Trigger pulse input
        output  : out std_logic -- Output pulse
    );
end entity;

architecture RTL of PulseGenerator is
    -- Pulse clock counter
    signal reg_Counter     : unsigned(HighBit(PULSE_LENGTH) downto 0) := (others => '0');
    signal reg_LastTrigger : std_logic                                := not TRIGGER_EDGE;
begin
    process (all)
    begin
        if rising_edge(clock) then
            if trigger /= reg_LastTrigger then
                if BOTH_EDGES = '1' or trigger = TRIGGER_EDGE then
                    reg_Counter <= to_unsigned(PULSE_LENGTH, reg_Counter'length);
                end if;
                reg_LastTrigger <= trigger;
            end if;

            if reg_Counter /= 0 then
                reg_Counter <= reg_Counter - 1;
            end if;
        end if;
    end process;

    output <= IDLE_OUTPUT when reg_Counter = 0 else
        not IDLE_OUTPUT;
end architecture;