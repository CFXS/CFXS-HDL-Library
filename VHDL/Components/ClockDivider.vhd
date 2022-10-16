library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.RequiredBits;

entity ClockDivider is
    generic (
        DIV_EDGE : std_logic := '1' -- Source clock edge to divide on
    );
    port (
        divider   : in unsigned;
        clock     : in std_logic;
        clock_div : out std_logic := not DIV_EDGE
    );
end entity;

architecture RTL of ClockDivider is
    signal reg_Counter : unsigned(RequiredBits(divider'length) - 1 downto 0) := (others => '0');
begin
    process (all)
    begin
        if clock'event and clock = DIV_EDGE then
            if reg_Counter /= unsigned(divider) then
                reg_Counter <= reg_Counter + 1;
                else
                reg_Counter <= (others => '0');
                clock_div   <= not clock_div;
            end if;
        end if;
    end process;
end architecture;