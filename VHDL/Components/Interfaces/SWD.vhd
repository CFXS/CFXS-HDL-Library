library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library CFXS;
use CFXS.Utils.all;

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
        request_SendLineReset      : in std_logic := '0'; -- Request to send line reset
        request_SendSwitchSequence : in std_logic := '0'; -- Request to send switch sequence
        request_ReadData           : in std_logic := '0'; -- Request SWD Read
        request_WriteData          : in std_logic := '0'; -- Request SWD Write

        -- Protocol
        swd_Header  : in std_logic_vector(7 downto 0);   -- SWD packet header to send
        swd_DataOut : in std_logic_vector(31 downto 0);  -- SWD data to send
        swd_DataIn  : out std_logic_vector(31 downto 0); -- SWD read transfer data

        -- Status
        status_Busy         : out std_logic; -- some operation is in progress
        status_ParityError  : out std_logic; -- SWD operation data bad parity bit
        status_TransferDone : out std_logic; -- SWD read/write transfer finished

        -- Pin mirror output (for debugging)
        mirror_target_swdio : out std_logic
    );
end entity;

architecture RTL of Interface_SWD is

    -- Clock divider counter from high speed module clock to target SWCLK
    signal clock_SWCLK_Divided : std_logic := '0';

    -- [SendLineReset / SendSwitchSequence]
    constant LINE_RESET_HIGH_BITS      : natural                       := 56 - 1;    -- at least 50 clocks required
    constant LINE_RESET_LOW_BITS       : natural                       := 2;         -- at least 2 idle bits required to complete reset
    constant SWD_SWITCH_SEQUENCE_DATA  : std_logic_vector(15 downto 0) := 16x"E79E"; -- JTAG -> SWD pattern
    signal reg_SwitchSequence_DataSent : boolean                       := false;     -- Switch data pattern sent

    -- SWDIO direction control
    type DataDirection_t is (DIR_INPUT, DIR_OUTPUT);
    signal dir_SWDIO : DataDirection_t := DIR_OUTPUT; -- default state is output

    -- SWCLK enable
    signal en_SWCLK : boolean := false;

    -- Pins
    signal reg_SWDIO : std_logic := '0';

    --------------------------------------
    -- [Protocol]

    -- Clocks sent by active state
    signal reg_SWD_ClocksSent : unsigned(HighBit(64) downto 0) := (others => '0');

    -- Main state machine state
    type SWD_State_t is (
        STATE_IDLE,
        STATE_IDLE_ON_CLOCK_FALL, -- Enter STATE_IDLE on protocol clock falling edge
        STATE_LINE_RESET,
        STATE_SWITCH_SEQUENCE,
        STATE_WRITE_PACKET,
        STATE_READ_PACKET
    );

    -- State steps
    type SWD_SubState_t is (
        SUB_IDLE,
        SUB_LINE_RESET_HIGH, -- High bit
        SUB_LINE_RESET_LOW,  -- Low bit
        SUB_SWITCH_DATA,     -- Switch sequence out
        SUB_SEND_HEADER,     -- Send packet header
        SUB_READ_ACK,        -- Read packet ack code
        SUB_WORD_OUT,        -- Write packet word
        SUB_WORD_IN          -- Read packet word
    );

    signal reg_SWD_State    : SWD_State_t    := STATE_IDLE;
    signal reg_SWD_SubState : SWD_SubState_t := SUB_IDLE;

    signal reg_SWD_DataBuffer   : std_logic_vector(32 downto 0); -- In/out shift register
    signal reg_SWD_HeaderBuffer : std_logic_vector(7 downto 0);  -- Header out, ack in register
    signal reg_SWD_Parity       : std_logic;                     -- In/out parity calculation register

    signal reg_SWCLK_EdgePulse : std_logic := '0'; -- Pulse on SWCLK edge synced to module clock
begin
    ------------------------------------------------------------------------
    -- Clock divider for SWCLK
    instance_SWDCLK_Divider : entity CFXS.ClockDivider
        port map(
            divider   => cfg_SWCLK_Divider,
            clock     => clock,
            clock_div => clock_SWCLK_Divided
        );

    ------------------------------------------------------------------------
    -- Generate 1 clock long pulse on protocol clock edge
    instance_ProtocolClockPulse : entity CFXS.PulseGenerator
        generic map(
            PULSE_LENGTH => 1,
            IDLE_OUTPUT  => '0',
            BOTH_EDGES   => '1'
        )
        port map(
            clock   => clock,
            trigger => clock_SWCLK_Divided, -- rising edge
            output  => reg_SWCLK_EdgePulse
        );

    ------------------------------------------------------------------------
    -- SWD State Machine
    process (all)
    begin
        if rising_edge(clock) then
            -- Select request to process if idle
            if (reg_SWD_State = STATE_IDLE_ON_CLOCK_FALL) then
                if (clock_SWCLK_Divided = '0') then
                    reg_SWD_State <= STATE_IDLE;
                end if;
            end if;

            if (reg_SWD_State = STATE_IDLE) then
                en_SWCLK           <= false;     -- disable clock
                dir_SWDIO          <= DIR_INPUT; -- disable output
                reg_SWD_ClocksSent <= (others => '0');

                if (request_SendLineReset = '1') then
                    -- Line reset request
                    reg_SWD_State    <= STATE_LINE_RESET;
                    reg_SWD_SubState <= SUB_LINE_RESET_HIGH;
                elsif (request_SendSwitchSequence = '1') then
                    -- Switch sequence request
                    reg_SWD_State               <= STATE_SWITCH_SEQUENCE;
                    reg_SWD_SubState            <= SUB_LINE_RESET_HIGH;
                    reg_SwitchSequence_DataSent <= false;
                elsif (request_ReadData) then
                    reg_SWD_State    <= STATE_READ_PACKET;
                    reg_SWD_SubState <= SUB_SEND_HEADER;
                    -- Park   : 1; 1
                    -- Stop   : 1; 0
                    -- Parity : 1;
                    -- A      : 2;
                    -- RnW    : 1;
                    -- APnDP  : 1;
                    -- Start  : 1; 1
                    reg_SWD_HeaderBuffer <= swd_Header;
                    reg_SWD_Parity       <= '0';
                end if;
            end if;

            if (reg_SWCLK_EdgePulse = '1') then -- synced rising edge of protocol clock
                if (reg_SWD_State = STATE_LINE_RESET or reg_SWD_State = STATE_SWITCH_SEQUENCE) then
                    if (clock_SWCLK_Divided = '1') then -- everything happens on rising edge
                        -- [Line Reset / Switch Sequence]
                        en_SWCLK  <= true;       -- enable clock
                        dir_SWDIO <= DIR_OUTPUT; -- enable output

                        if (reg_SWD_SubState = SUB_LINE_RESET_HIGH) then
                            -- [SUB_LINE_RESET_HIGH]
                            reg_SWDIO <= '1';
                            if (reg_SWD_ClocksSent /= LINE_RESET_HIGH_BITS) then
                                reg_SWD_ClocksSent <= reg_SWD_ClocksSent + 1;
                            else
                                if (reg_SWD_State = STATE_SWITCH_SEQUENCE and reg_SwitchSequence_DataSent = false) then
                                    reg_SWD_SubState                <= SUB_SWITCH_DATA;
                                    reg_SWD_DataBuffer(15 downto 0) <= SWD_SWITCH_SEQUENCE_DATA;
                                else
                                    reg_SWD_SubState <= SUB_LINE_RESET_LOW;
                                end if;
                                reg_SWD_ClocksSent <= (others => '0');
                            end if;
                        elsif (reg_SWD_SubState = SUB_LINE_RESET_LOW) then
                            -- [SUB_LINE_RESET_LOW]
                            reg_SWDIO <= '0';
                            if (reg_SWD_ClocksSent /= LINE_RESET_LOW_BITS) then
                                reg_SWD_ClocksSent <= reg_SWD_ClocksSent + 1;
                            else
                                reg_SWD_SubState <= SUB_IDLE;
                                reg_SWD_State    <= STATE_IDLE;
                            end if;
                        elsif (reg_SWD_SubState = SUB_SWITCH_DATA) then
                            -- [SUB_SWITCH_DATA]
                            reg_SWDIO <= reg_SWD_DataBuffer(0);
                            if (reg_SWD_ClocksSent /= 16) then
                                reg_SWD_ClocksSent <= reg_SWD_ClocksSent + 1;
                                reg_SWD_DataBuffer <= '0' & reg_SWD_DataBuffer(reg_SWD_DataBuffer'high downto 1);
                            else
                                reg_SWD_SubState            <= SUB_LINE_RESET_HIGH;
                                reg_SwitchSequence_DataSent <= true;
                                reg_SWD_ClocksSent          <= (others => '0');
                            end if;
                        end if;
                    end if;
                elsif (reg_SWD_State = STATE_READ_PACKET or reg_SWD_State = STATE_WRITE_PACKET) then
                    en_SWCLK <= true;
                    -- [Send Header and Read ACK]
                    if (reg_SWD_SubState = SUB_SEND_HEADER and clock_SWCLK_Divided = '0') then -- rising edge data phase
                        -- Send header
                        if (reg_SWD_ClocksSent /= 8) then
                            -- send header data
                            dir_SWDIO            <= DIR_OUTPUT;
                            reg_SWDIO            <= reg_SWD_HeaderBuffer(0);
                            reg_SWD_HeaderBuffer <= '0' & reg_SWD_HeaderBuffer(reg_SWD_HeaderBuffer'high downto 1);
                            reg_SWD_ClocksSent   <= reg_SWD_ClocksSent + 1;
                        else
                            -- turnaround cycle to read ack
                            dir_SWDIO            <= DIR_INPUT;
                            reg_SWD_SubState     <= SUB_READ_ACK;
                            reg_SWD_ClocksSent   <= (others => '0');
                            reg_SWD_HeaderBuffer <= (others => '0');
                        end if;
                    elsif (reg_SWD_SubState = SUB_READ_ACK and clock_SWCLK_Divided = '1') then -- falling edge data phase
                        -- Read ack code
                        if (reg_SWD_ClocksSent /= 3) then
                            -- shift in from swdio
                            -- TODO: check if small range shift is more LE-efficient
                            reg_SWD_HeaderBuffer <= reg_SWD_HeaderBuffer(reg_SWD_HeaderBuffer'high - 1 downto 0) & target_swdio;
                            reg_SWD_ClocksSent   <= reg_SWD_ClocksSent + 1;
                        else
                            reg_SWD_ClocksSent <= (others => '0');
                            reg_SWD_SubState   <= SUB_WORD_IN;
                            dir_SWDIO          <= DIR_INPUT;
                        end if;
                    end if;
                    -- no elsif because there is no turnaround cycle
                    if (reg_SWD_SubState = SUB_WORD_IN and clock_SWCLK_Divided = '1') then -- falling edge data phase
                        if (reg_SWD_ClocksSent /= 33) then
                            reg_SWD_Parity     <= reg_SWD_Parity xor target_swdio;
                            reg_SWD_DataBuffer <= reg_SWD_DataBuffer(reg_SWD_DataBuffer'high - 1 downto 0) & target_swdio;
                            reg_SWD_ClocksSent <= reg_SWD_ClocksSent + 1;
                        else
                            reg_SWD_State      <= STATE_IDLE;
                            reg_SWD_SubState   <= SUB_IDLE;
                            reg_SWD_ClocksSent <= (others => '0');
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

    -- Data buffer to data input reverse order
    gen_DataInReverse : for i in 0 to swd_DataIn'high generate
        swd_DataIn(i) <= reg_SWD_DataBuffer(reg_SWD_DataBuffer'high - i);
    end generate;

    status_ParityError <= reg_SWD_Parity; -- If parity register is 1, then parity is not correct

    ------------------------------------------------------------------------
    -- [Status signals]

    -- Busy signal
    status_Busy <= '1' when reg_SWD_State /= STATE_IDLE else
        '0';
end architecture;