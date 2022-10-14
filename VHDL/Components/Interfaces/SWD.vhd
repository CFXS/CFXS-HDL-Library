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

    -- Requests
    signal reg_SendLineReset      : std_logic := '0'; -- request to send line reset
    signal reg_SendSwitchSequence : std_logic := '0'; -- request to send switch sequence

    -- [SendLineReset]
    constant LINE_RESET_HIGH_BITS   : natural := 60 - 1; -- at least 50 clocks required
    constant LINE_RESET_LOW_BITS    : natural := 4;      -- at least 2 idle bits required to complete reset
    signal reg_LineReset_InProgress : boolean := false;
    -- Clocks sent
    signal reg_LineReset_ClocksSent : unsigned(RequiredBits(LINE_RESET_HIGH_BITS) - 1 downto 0) := (others => '0');

    -- SWDIO direction control
    type DataDirection_t is (DIR_INPUT, DIR_OUTPUT);
    signal dir_SWDIO : DataDirection_t := DIR_OUTPUT; -- default state is output

    -- SWCLK enable
    signal en_SWCLK : boolean := false;

    -- Pins
    signal reg_SWDIO : std_logic := '0';

    --------------------------------------
    -- [Protocol]

    -- Main state machine state
    type SWD_State_t is (
        STATE_IDLE,
        STATE_LINE_RESET,
        STATE_SWITCH_SEQUENCE
    );

    -- State steps
    type SWD_SubState_t is (
        SUB_IDLE,
        SUB_LINE_RESET_HIGH,
        SUB_LINE_RESET_LOW,
        SUB_SWITCH_DATA
    );

    signal reg_SWD_State        : SWD_State_t    := STATE_IDLE;
    signal reg_SWD_NextState    : SWD_State_t    := STATE_IDLE;
    signal reg_SWD_SubState     : SWD_SubState_t := SUB_IDLE;
    signal reg_SWD_NextSubState : SWD_SubState_t := SUB_IDLE;

    signal reg_SWCLK_TriggerPulse : std_logic := '0'; -- Pulse on SWCLK rising edge synced to module clock
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

    instance_ProtocolClockPulse : entity CFXS.PulseGenerator
        generic map(
            IDLE_OUTPUT  => '0',
            PULSE_LENGTH => 1
        )
        port map(
            clock   => clock,
            trigger => clock_SWCLK_Divided,
            output  => reg_SWCLK_TriggerPulse
        );

    process (all)
    begin
        if rising_edge(clock) then
            -- Select request to process if idle
            if (reg_SWD_State = STATE_IDLE) then
                en_SWCLK  <= false;     -- disable clock
                dir_SWDIO <= DIR_INPUT; -- disable output

                -- Line reset request
                if (request_SendLineReset = '1') then
                    reg_SWD_State            <= STATE_LINE_RESET;
                    reg_SWD_SubState         <= SUB_LINE_RESET_HIGH;
                    reg_LineReset_ClocksSent <= (others => '0');
                end if;
            end if;

            if (reg_SWCLK_TriggerPulse = '1') then -- synced rising edge of protocol clock
                -- [LINE_RESET]
                if (reg_SWD_State = STATE_LINE_RESET) then
                    en_SWCLK  <= true;       -- enable clock
                    dir_SWDIO <= DIR_OUTPUT; -- enable output
                    if (reg_SWD_SubState = SUB_LINE_RESET_HIGH) then
                        reg_SWDIO <= '1';
                        if (reg_LineReset_ClocksSent /= to_unsigned(LINE_RESET_HIGH_BITS, RequiredBits(LINE_RESET_HIGH_BITS))) then
                            reg_LineReset_ClocksSent <= reg_LineReset_ClocksSent + 1;
                        else
                            reg_SWD_SubState         <= SUB_LINE_RESET_LOW;
                            reg_LineReset_ClocksSent <= (others => '0');
                        end if;
                    elsif (reg_SWD_SubState = SUB_LINE_RESET_LOW) then
                        reg_SWDIO <= '0';
                        if (reg_LineReset_ClocksSent /= to_unsigned(LINE_RESET_LOW_BITS, RequiredBits(LINE_RESET_LOW_BITS))) then
                            reg_LineReset_ClocksSent <= reg_LineReset_ClocksSent + 1;
                        else
                            reg_SWD_SubState <= SUB_IDLE;
                            reg_SWD_State    <= STATE_IDLE;
                        end if;
                    end if;
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

    target_swclk <= clock_SWCLK_Divided when en_SWCLK else
        '1';
    -------------------------------------
    -- [Status signals]
    -- Busy signal
    status_Busy <= '1' when reg_SWD_State /= STATE_IDLE else
        '0';
end architecture;