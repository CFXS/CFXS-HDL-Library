library ieee;
use ieee.std_logic_1164.all;

package Utils is
    -- Number of bits required to represent the input in vector form
    function RequiredBits(n : integer) return natural;
    -- High bit index of vector containing number n
    function HighBit(n : integer) return natural;
    function NanosecondsToCycles(t : natural; freq : natural) return natural;
    function MicrosecondsToCycles(t : natural; freq : natural) return natural;
    function MillisecondsToCycles(t : natural; freq : natural) return natural;
    function SecondsToCycles(t : natural; freq : natural) return natural;
end package;

package body Utils is
    -- Number of bits required to represent the input in vector form
    function RequiredBits(n : integer) return natural is
        variable temp           : integer;
        variable bits           : natural;
    begin
        temp := n;
        while(temp > 0) loop
            temp := temp / 2;
            bits := bits + 1;
        end loop;
        return bits;
    end function RequiredBits;

    -- High bit index of vector containing number n
    function HighBit(n : integer) return natural is
    begin
        return RequiredBits(n) - 1;
    end function HighBit;

    function NanosecondsToCycles(t : natural; freq : natural) return natural is begin
        return freq / 1_000_000_000 * t;
    end function NanosecondsToCycles;

    function MicrosecondsToCycles(t : natural; freq : natural) return natural is begin
        return freq / 1_000_000 * t;
    end function MicrosecondsToCycles;

    function MillisecondsToCycles(t : natural; freq : natural) return natural is begin
        return freq / 1_000 * t;
    end function MillisecondsToCycles;

    function SecondsToCycles(t : natural; freq : natural) return natural is begin
        return freq * t;
    end function SecondsToCycles;
end package body;