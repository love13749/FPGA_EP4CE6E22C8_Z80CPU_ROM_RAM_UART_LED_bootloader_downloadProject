library ieee;
use ieee.std_logic_1164.all;
use  IEEE.STD_LOGIC_ARITH.all;
use  IEEE.STD_LOGIC_UNSIGNED.all;

entity Microcomputer is
	port(
		n_reset		: in std_logic;    -- 复位引脚
		clk			: in std_logic;    -- 时钟引脚
		rxd1			: in std_logic;    -- USART接收引脚
		txd1			: out std_logic;   -- USART发送引脚
		leds			: out std_logic_vector(7 downto 0) -- LED并行输出引脚
	);
end Microcomputer;

architecture struct of Microcomputer is

	signal n_WR							: std_logic;                     -- Z80CPU写入信号
	signal n_RD							: std_logic;                     -- Z80CPU读取信号
	signal cpuAddress					: std_logic_vector(15 downto 0); -- Z80CPU的16位地址总线
	signal cpuDataOut					: std_logic_vector(7 downto 0);  -- Z80CPU的8位数据输入总线
	signal cpuDataIn					: std_logic_vector(7 downto 0);  -- Z80CPU的8位数据输出总线

	signal basRomData					: std_logic_vector(7 downto 0);  -- Z80CPU的控制信号ROM输出
	signal internalRam1DataOut		: std_logic_vector(7 downto 0);  -- Z80CPU的控制信号RAM输出
	signal internalRam2DataOut		: std_logic_vector(7 downto 0);  -- Z80CPU的控制信号第二个RAM输出
	signal interface1DataOut		: std_logic_vector(7 downto 0);  -- Z80CPU的控制信号USART输出

	signal n_memWR						: std_logic :='1'; -- 内存写信号
	signal n_memRD 					: std_logic :='1'; -- 内存读信号

	signal n_ioWR						: std_logic :='1'; -- IO写信号
	signal n_ioRD 						: std_logic :='1'; -- IO读信号
	
	signal n_MREQ						: std_logic :='1'; -- 内存就绪信号
	signal n_IORQ						: std_logic :='1'; -- IO就绪信号

	signal n_int1						: std_logic :='1'; -- 中断1
	signal n_int2						: std_logic :='1'; -- 中断2
	
	signal n_internalRam1CS			: std_logic :='1'; --
	signal n_internalRam2CS			: std_logic :='1';
	signal n_basRomCS					: std_logic :='1';
	signal n_interface1CS			: std_logic :='1';
	signal n_aaronCS					: std_logic :='1';

	signal serialClkCount			: std_logic_vector(15 downto 0);
	signal cpuClkCount				: std_logic_vector(5 downto 0); 
	signal cpuClock					: std_logic;
	signal serialClock				: std_logic;
	
begin

cpu1 : entity work.t80s
generic map(mode => 1, t2write => 1, iowait => 0)
port map(
reset_n => n_reset,
clk_n => cpuClock,
wait_n => '1',
int_n => '1',
nmi_n => '1',
busrq_n => '1',
mreq_n => n_MREQ,
iorq_n => n_IORQ,
rd_n => n_RD,
wr_n => n_WR,
a => cpuAddress,
di => cpuDataIn,
do => cpuDataOut);

rom1 : entity work.Z80_BASIC_ROM -- 8KB BASIC
port map(
address => cpuAddress(12 downto 0),
clock => clk,
q => basRomData
);

ram1: entity work.InternalRam4K
port map
(
address => cpuAddress(11 downto 0),
clock => clk,
data => cpuDataOut,
wren => not(n_memWR or n_internalRam1CS),
q => internalRam1DataOut
);

io1 : entity work.bufferedUART
port map(
clk => clk,
n_wr => n_interface1CS or n_ioWR,
n_rd => n_interface1CS or n_ioRD,
n_int => n_int1,
regSel => cpuAddress(0),
dataIn => cpuDataOut,
dataOut => interface1DataOut,
rxClock => serialClock,
txClock => serialClock,
rxd => rxd1,
txd => txd1,
n_cts => '0',
n_dcd => '0'
);

io2 : entity work.aaron
port map(
n_wr => n_aaronCS or n_ioWR,
dataIn => cpuDataOut,
dataOut => leds,
reset_n => n_reset
);

n_ioWR <= n_WR or n_IORQ;
n_memWR <= n_WR or n_MREQ;
n_ioRD <= n_RD or n_IORQ;
n_memRD <= n_RD or n_MREQ;

n_basRomCS <= '0' when cpuAddress(15 downto 13) = "000" else '1'; --8K at bottom of memory
n_interface1CS <= '0' when cpuAddress(7 downto 1) = "1000000" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 2 Bytes $80-$81
n_aaronCS <= '0' when cpuAddress(7 downto 1) = "1001000" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 2 Bytes $90-$91
n_internalRam1CS <= '0' when cpuAddress(15 downto 12) = "0010" else '1';

cpuDataIn <=
interface1DataOut when n_interface1CS = '0' else
basRomData when n_basRomCS = '0' else
internalRam1DataOut when n_internalRam1CS= '0' else
x"FF";

serialClock <= serialClkCount(15);
process (clk)
begin
if rising_edge(clk) then

if cpuClkCount < 4 then -- 4 = 10MHz, 3 = 12.5MHz, 2=16.6MHz, 1=25MHz
cpuClkCount <= cpuClkCount + 1;
else
cpuClkCount <= (others=>'0');
end if;
if cpuClkCount < 2 then -- 2 when 10MHz, 2 when 12.5MHz, 2 when 16.6MHz, 1 when 25MHz
cpuClock <= '0';
else
cpuClock <= '1';
end if;

-- Serial clock DDS
-- 50MHz master input clock:
-- Baud Increment
-- 115200 2416
-- 38400 805
-- 19200 403
-- 9600 201
-- 4800 101
-- 2400 50
serialClkCount <= serialClkCount + 2416;
end if;
end process;
end;
