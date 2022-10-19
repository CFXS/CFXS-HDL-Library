library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.all;

entity ClockDivider is
    generic (
        DIV_EDGE : std_logic := '1' -- Source clock edge to divide on
    );
    port (
        divider   : in unsigned;
        clock     : in std_logic;
        clock_div : out std_logic
    );
end entity;

architecture RTL of ClockDivider is
    signal reg_Counter  : unsigned(divider'length - 1 downto 0) := (others => '0');
    signal reg_ClockOut : std_logic                             := not DIV_EDGE;
begin
    process (all)
    begin
        if clock'event and clock = DIV_EDGE then
            if reg_Counter /= unsigned(divider) then
                reg_Counter <= reg_Counter + 1;
            else
                reg_Counter  <= (others => '0');
                reg_ClockOut <= not reg_ClockOut;
            end if;
        end if;
    end process;

    clock_div <= reg_ClockOut;
end architecture;