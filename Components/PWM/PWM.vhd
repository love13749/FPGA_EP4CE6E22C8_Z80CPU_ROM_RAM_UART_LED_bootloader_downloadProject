library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
	use ieee.std_logic_unsigned.all;

entity PWM is
	port(
		clk     : in std_logic;                      -- 27MHz 主时钟
		n_wr    : in std_logic;                      -- I/O 写选通
		n_rd    : in std_logic;                      -- I/O 读选通
		regSel  : in std_logic_vector(1 downto 0);   -- 寄存器选择 (00=CTRL,01=PRD,10=CCR,11=CNT)
		dataIn  : in std_logic_vector(7 downto 0);   -- CPU 写入数据
		dataOut : out std_logic_vector(7 downto 0);  -- CPU 读取数据
		pwm_out : out std_logic_vector(7 downto 0)   -- PWM 输出信号
	);
end PWM;


architecture rtl of PWM is
    -- 寄存器定义
    signal CTRL : std_logic_vector(7 downto 0) := (others => '0');  -- 控制寄存器，IO地址为$84
    signal PRD  : std_logic_vector(7 downto 0) := (others => '0');  -- 周期寄存器，IO地址为$85
    signal CCR  : std_logic_vector(7 downto 0) := (others => '0');  -- 占空比寄存器，IO地址为$86
    signal CNT  : std_logic_vector(7 downto 0) := (others => '0');  -- 计数寄存器，IO地址为$87
    signal SR   : std_logic_vector(7 downto 0) := (others => '0');  -- 状态寄存器
    signal pwm_out_internal : std_logic_vector(7 downto 0) := (others => '0'); 

begin
    -------------------------------------------------------------------
    -- 读寄存器 (保持不变，组合逻辑)
    -------------------------------------------------------------------
    process(n_rd, regSel, CTRL, PRD, CCR, CNT, SR)
    begin
        dataOut <= x"FF";  -- 默认值
        if n_rd = '0' then
            case regSel is
                when "00" => dataOut <= CTRL;
                when "01" => dataOut <= PRD;
                when "10" => dataOut <= CCR;
                when "11" => dataOut <= CNT;   
                when others => null;
            end case;
        end if;
    end process;

    -- 状态寄存器 (保持不变，组合逻辑)
    SR(0) <= '1' when CNT = x"00" else '0'; 
    SR(7 downto 1) <= (others => '0');

    -------------------------------------------------------------------
    -- 核心逻辑与写操作 (统一整合到 clk 进程中)
    -------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- 1. CPU 写寄存器：将 n_wr 作为写使能信号 (这里假定 n_wr 是低电平有效)
            if n_wr = '0' then
                case regSel is
                    when "00" => CTRL <= dataIn;
                    when "01" => PRD <= dataIn;
                    when "10" => CCR <= dataIn;
                    when others => null;
                end case;
            end if;

            -- 2. 软件复位逻辑 (使用 CTRL 的第 7 位)
            if CTRL(7) = '1' then
                -- 软件复位：把计数器清零，PWM输出关闭
                CNT <= (others => '0');
                pwm_out_internal <= "00000000";
            elsif CTRL(0) = '1' then
                -- 3. PWM 使能状态
                if CNT = PRD then
                    CNT <= (others => '0');
                else
                    CNT <= CNT + 1;
                end if;

                -- 4. 占空比比较逻辑
                if CNT < CCR then
                    pwm_out_internal <= "11111111";
                else
                    pwm_out_internal <= "00000000";
                end if;
            else
                -- 关闭状态：输出低电平
                pwm_out_internal <= "00000000";
            end if;
        end if;
    end process;

    -- 极性选择
    pwm_out <= pwm_out_internal when CTRL(1) = '1' else not pwm_out_internal;

end rtl;