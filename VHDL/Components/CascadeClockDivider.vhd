library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.all;

entity CascadeClockDivider is
    generic (
        N        : natural;         -- Cascade power - division = clock/(2^N)
        DIV_EDGE : std_logic := '1' -- Source clock edge to divide on
    );
    port (
        clock     : in std_logic;
        clock_div : out std_logic
    );
end entity;

architecture RTL of CascadeClockDivider is
    signal reg_Counter : unsigned(HighBit(2 ** (N - 1)) downto 0) := (others => '0');
begin
    process (all)
    begin
        if clock'event and clock = DIV_EDGE then
            reg_Counter <= reg_Counter + 1;
        end if;
    end process;

    clock_div <= reg_Counter(N - 1);
end architecture;