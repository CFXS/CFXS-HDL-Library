library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.RequiredBits;

entity FixedClockDivider is
    generic (
        DIVIDER  : natural;         -- Divider value
        DIV_EDGE : std_logic := '1' -- Source clock edge to divide on
    );
    port (
        clock     : in std_logic;
        clock_div : out std_logic := not DIV_EDGE
    );
end entity;

architecture RTL of FixedClockDivider is
    signal reg_Counter : unsigned(RequiredBits(DIVIDER) - 1 downto 0) := (others => '0');
begin
    process (all)
    begin
        if clock'event and clock = DIV_EDGE then
            if reg_Counter /= to_unsigned(DIVIDER - 1, reg_Counter'length) then
                reg_Counter <= reg_Counter + 1;
            else
                reg_Counter <= (others => '0');
                clock_div   <= not clock_div;
            end if;
        end if;
    end process;
end architecture;