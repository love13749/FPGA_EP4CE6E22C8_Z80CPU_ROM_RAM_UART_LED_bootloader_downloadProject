library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
	use ieee.std_logic_unsigned.all;

entity aaron is
	port (
		n_wr    : in  std_logic;
		reset_n    : in  std_logic;
		dataIn  : in  std_logic_vector(7 downto 0);
		dataOut  : out  std_logic_vector(7 downto 0)
   );
end aaron;

architecture rtl of aaron is

signal n_int_internal   : std_logic := '1';

begin
	process(n_wr)
	begin
		if reset_n = '0' then   --复位信号时
			dataOut(0) <= '0';   --初始状态为01010101B
			dataOut(1) <= '1';
			dataOut(2) <= '0';
			dataOut(3) <= '1';
			dataOut(4) <= '0';
			dataOut(5) <= '1';
			dataOut(6) <= '0';
			dataOut(7) <= '1';
		elsif rising_edge(n_wr) then -- 写入LED灯控制信号
			dataOut <= dataIn;        -- 输出数据信号
		end if;
	end process;
 end rtl;
