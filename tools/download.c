#include <windows.h>
#include <stdio.h>

HANDLE hSerial;  // 串口句柄

// 打印接收到的数据
void print_text(const unsigned char *data, DWORD len) 
{
    for (DWORD i = 0; i < len; i++)
        printf("%c", data[i]);
    printf("\n");
}

// 重新发送 project.bin 文件
int send_project_bin() 
{
    FILE *fp = fopen("D:\\FPGAProject\\MC\\MC\\Z80Project\\Object\\project.bin", "r");
    if (!fp) 
    {
        printf("Failed to open project.bin!\n");
        return -1;
    }

    unsigned char buffer[4096];
    DWORD bytesRead, bytesWritten;
    while ((bytesRead = fread(buffer, 1, sizeof(buffer), fp)) > 0) 
    {
        if (!WriteFile(hSerial, buffer, bytesRead, &bytesWritten, NULL)) 
        {
            printf("WriteFile error\n");
            fclose(fp);
            return -1;
        }
        printf("Sent %d bytes\n", bytesWritten);
    }
    fclose(fp);
    printf("File sent successfully!\n");
    return 0;
}

int main() 
{
    // 1. 打开串口 COM4
    hSerial = CreateFile("\\\\.\\COM4",
                         GENERIC_READ | GENERIC_WRITE,
                         0, NULL, OPEN_EXISTING,
                         FILE_ATTRIBUTE_NORMAL, NULL);
    if (hSerial == INVALID_HANDLE_VALUE) 
    {
        printf("Failed to open COM4!\n");
        return 1;
    }

    // 2. 配置串口参数 (115200,8,N,1)
    DCB dcb = {0};
    dcb.DCBlength = sizeof(DCB);
    if (!GetCommState(hSerial, &dcb)) 
    {
        printf("GetCommState failed\n");
        CloseHandle(hSerial);
        return 1;
    }
    dcb.BaudRate = CBR_115200;
    dcb.ByteSize = 8;
    dcb.Parity   = NOPARITY;
    dcb.StopBits = ONESTOPBIT;
    if (!SetCommState(hSerial, &dcb)) 
    {
        printf("SetCommState failed\n");
        CloseHandle(hSerial);
        return 1;
    }

    // 3. 设置超时
    COMMTIMEOUTS timeouts = {0};
    timeouts.ReadIntervalTimeout         = 50;
    timeouts.ReadTotalTimeoutMultiplier  = 0;
    timeouts.ReadTotalTimeoutConstant    = 100;
    timeouts.WriteTotalTimeoutMultiplier = 50;
    timeouts.WriteTotalTimeoutConstant   = 100;
    if (!SetCommTimeouts(hSerial, &timeouts)) 
    {
        printf("SetCommTimeouts failed\n");
        CloseHandle(hSerial);
        return 1;
    }

    // 4. 初次发送文件
    if (send_project_bin() != 0) 
    {
        CloseHandle(hSerial);
        return 1;
    }
    printf("Now monitoring COM4...\n");
    printf("Press ESC to exit, Ctrl+D to re-download project.bin.\n\n");

    // 5. 获取控制台输入句柄
    HANDLE hStdin = GetStdHandle(STD_INPUT_HANDLE);
    if (hStdin == INVALID_HANDLE_VALUE) 
    {
        printf("Failed to get stdin handle\n");
        CloseHandle(hSerial);
        return 1;
    }

    // 6. 主循环：接收串口数据 + 响应键盘
    unsigned char rxBuf[1024];
    DWORD rxLen;
    INPUT_RECORD inputRecord;
    DWORD eventsRead;
    BOOL exitFlag = FALSE;

    while (!exitFlag) 
    {
        // 6.1 读取串口数据
        if (ReadFile(hSerial, rxBuf, sizeof(rxBuf), &rxLen, NULL) && rxLen > 0) 
        {
            printf("Received %d bytes: ", rxLen);
            print_text(rxBuf, rxLen);
        }

        // 6.2 非阻塞地处理键盘事件
        while (PeekConsoleInput(hStdin, &inputRecord, 1, &eventsRead) && eventsRead > 0) 
        {
            if (!ReadConsoleInput(hStdin, &inputRecord, 1, &eventsRead))
                break;

            if (inputRecord.EventType == KEY_EVENT && inputRecord.Event.KeyEvent.bKeyDown) 
            {
                WORD vk = inputRecord.Event.KeyEvent.wVirtualKeyCode;
                DWORD ctrlState = inputRecord.Event.KeyEvent.dwControlKeyState;

                // 检测 ESC 键 → 退出
                if (vk == VK_ESCAPE) 
                {
                    printf("\nUser exit.\n");
                    exitFlag = TRUE;
                    break;
                }

                // 检测 Ctrl+D → 重新下载文件
                // 字母 D 的虚拟键码为 0x44
                if (vk == 0x44 &&
                    (ctrlState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED))) 
                {
                    printf("\nCtrl+D pressed: re-downloading project.bin...\n");
                    if (send_project_bin() != 0)
                        printf("Re-download failed!\n");
                }
            }
        }

        Sleep(1);  // 降低 CPU 占用
    }

    CloseHandle(hSerial);
    return 0;
}