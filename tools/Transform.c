/*
    转换project.hex文件为可直接下载的bit流文件project.bin文件
*/

#include<stdio.h>

char ch;

int main()
{
    freopen("D:\\FPGAProject\\MC\\MC\\Z80Project\\Object\\project.bin", "rb", stdin);  // 重定向标准输入到project.hex文件
    freopen("D:\\FPGAProject\\MC\\MC\\Z80Project\\Object\\project.bin", "wb", stdout); // 重定向标准输出到project.bin文件
    
    while((ch = getchar()) != EOF)
    {
        if(ch != '\n' && ch != '\r') putchar(ch);
    }

    putchar('\r');
    putchar('\n');

    return 0;
}