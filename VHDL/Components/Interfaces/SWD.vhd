library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.RequiredBits;

-- ARM SerialWireDebug Interface
entity Interface_SWD is
    generic (
        SWCLK_DIV_WIDTH  : natural; -- Register width for SWCLK divider counter
        USE_SWDIO_MIRROR : boolean := false;

        SWCLK_DIV_EDGE : std_logic := '1'; -- Edge to divide module clock on
        ignore         : natural   := 0
    );
    port (
        clock : in std_logic;

        -- Config value inputs
        cfg_SWCLK_Divider : in unsigned(SWCLK_DIV_WIDTH - 1 downto 0);

        -- Signals to target device
        target_swclk : out std_logic;
        target_swdio : inout std_logic;

        -- Requests
        request_SendLineReset      : in std_logic := '0'; -- request to send line reset
        request_SendSwitchSequence : in std_logic := '0'; -- request to send switch sequence

        -- Status
        status_Busy : out std_logic; -- some operation is in progress

        -- Pin mirror output (for debugging)
        mirror_target_swdio : out std_logic
    );
end entity;

architecture RTL of Interface_SWD is
    -- Clock divider counter from high speed module clock to target SWCLK
    signal reg_SWCLK_DividerCounter : unsigned(SWCLK_DIV_WIDTH - 1 downto 0) := (others => '0');
    signal clock_SWCLK_Divided      : std_logic                              := '0';

    -- Status registers
    signal reg_Status_Busy : std_logic := '0';

    -- Requests
    signal reg_SendLineReset      : std_logic := '0'; -- request to send line reset
    signal reg_SendSwitchSequence : std_logic := '0'; -- request to send switch sequence

    -- [SendLineReset]
    constant LINE_RESET_HIGH_BITS   : natural := 56; -- at least 50 clocks required
    constant LINE_RESET_LOW_BITS    : natural := 2;  -- at least 2 idle bits required to complete reset
    signal reg_LineReset_InProgress : boolean := false;
    -- high bits to send
    signal reg_LineReset_HighBitsToSend : unsigned(RequiredBits(LINE_RESET_HIGH_BITS) - 1 downto 0) := (others => '0');
    -- low bits to send
    signal reg_LineReset_LowBitsToSend : unsigned(RequiredBits(LINE_RESET_LOW_BITS) - 1 downto 0) := (others => '0');

    -- SWDIO direction control
    type DataDirection_t is (DIR_INPUT, DIR_OUTPUT);
    signal dir_SWDIO : DataDirection_t := DIR_OUTPUT; -- default state is output

    -- SWCLK enable
    signal en_SWCLK : boolean := false;

    -- Pins
    signal reg_SWDIO : std_logic := '0';
begin
    ------------------------------------------------------------------------
    -- Clock divider for SWCLK
    process (clock, cfg_SWCLK_Divider)
    begin
        if clock'event and clock = SWCLK_DIV_EDGE then
            if reg_SWCLK_DividerCounter < cfg_SWCLK_Divider then
                reg_SWCLK_DividerCounter <= reg_SWCLK_DividerCounter + 1;
            else
                reg_SWCLK_DividerCounter <= (others => '0');
                clock_SWCLK_Divided      <= not clock_SWCLK_Divided;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- [request_SendLineReset]
    -- LINE_RESET_HIGH_BITS
    -- LINE_RESET_LOW_BITS
    -- reg_LineReset_InProgress
    -- reg_LineReset_HighBitsToSend
    -- reg_LineReset_LowBitsToSend
    process (clock_SWCLK_Divided, request_SendLineReset)
    begin
        if rising_edge(clock_SWCLK_Divided) then
            if reg_Status_Busy = '0' and not reg_LineReset_InProgress and (request_SendLineReset = '1') then -- setup
                reg_LineReset_InProgress     <= true;
                reg_LineReset_HighBitsToSend <= to_unsigned(LINE_RESET_HIGH_BITS, RequiredBits(LINE_RESET_HIGH_BITS));
                reg_LineReset_LowBitsToSend  <= to_unsigned(LINE_RESET_LOW_BITS, RequiredBits(LINE_RESET_LOW_BITS));
                reg_SWDIO                    <= '1';
            else -- send
                if reg_LineReset_HighBitsToSend /= to_unsigned(0, reg_LineReset_HighBitsToSend'length) then
                    reg_LineReset_HighBitsToSend <= reg_LineReset_HighBitsToSend - 1;
                elsif reg_LineReset_LowBitsToSend /= to_unsigned(0, reg_LineReset_LowBitsToSend'length) then
                    reg_LineReset_LowBitsToSend <= reg_LineReset_LowBitsToSend - 1;
                    reg_SWDIO                   <= '0';
                else
                    reg_LineReset_InProgress <= false;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- [SWD] signal mapping
    -- SWDIO direction selection
    target_swdio <= reg_SWDIO when dir_SWDIO = DIR_OUTPUT else
        'Z';
    -- SWDIO mirror to debug output
    mirror_target_swdio <= '0' when USE_SWDIO_MIRROR = false else
        reg_SWDIO when dir_SWDIO = DIR_OUTPUT else
        target_swdio;
    -- clock enable

    en_SWCLK <= reg_LineReset_InProgress;

    target_swclk <= clock_SWCLK_Divided when en_SWCLK else
        '1';
    -------------------------------------
    -- [Status signals]
    -- Busy signal
    reg_Status_Busy <= '1' when reg_LineReset_InProgress else
        '0';
    status_Busy <= reg_Status_Busy;
end architecture;
