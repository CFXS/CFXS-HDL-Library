library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;

-- Fixed stability cycle debounce
entity FixedDebounce is
    generic (
        STABLE_CYCLES  : natural;          -- Cycles required until input is moved to output
        N              : natural   := 1;   -- Number of debounce channels
        INITIAL_OUTPUT : std_logic := '0'; -- Initial output state
        CLOCK_EDGE     : std_logic := '1'  -- Process clock edge
    );
    port (
        nreset : in std_logic := '0'; -- optional
        clock  : in std_logic;
        input  : in std_logic_vector(N - 1 downto 0);
        output : out std_logic_vector(N - 1 downto 0)
    );
end entity;

architecture RTL of FixedDebounce is
    -- bits required to hold counter counting to STABLE_CYCLES - 1
    constant REQUIRED_BITS : natural := CFXS.Utils.RequiredBits(STABLE_CYCLES);
    -- Array type of counter values
    type CounterArray_t is array (N - 1 downto 0) of unsigned(REQUIRED_BITS - 1 downto 0);
    -- Counter registers for each channel
    signal reg_StableCount : CounterArray_t := (others => (others => '0'));
    -- Current stable output state register
    signal reg_OutputState : std_logic_vector(N - 1 downto 0) := (others => INITIAL_OUTPUT);
begin
    process (all)
    begin
        if nreset = '0' then
            -- async reset
            reg_StableCount <= (others => (others => '0'));
            reg_OutputState <= (others => INITIAL_OUTPUT);
        elsif clock'event and clock = CLOCK_EDGE then
            for i in 0 to N - 1 loop
                if input(i) /= reg_OutputState(i) then
                    -- count stable cycles if input is not the same as stable output
                    reg_StableCount(i) <= reg_StableCount(i) + 1;

                    if reg_StableCount(i) = to_unsigned(STABLE_CYCLES, REQUIRED_BITS) then
                        -- move input to output if input has been stable for required number of cycles
                        reg_OutputState(i) <= input(i);
                    end if;
                else
                    reg_StableCount(i) <= (others => '0');
                end if;
            end loop;
        end if;
    end process;

    output <= reg_OutputState;
end architecture;