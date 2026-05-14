@echo off 
cd D:\FPGAProject\MC\MC\Z80Project
sjasmplus project.asm --hex=Object\project.hex
D:\FPGAProject\MC\MC\tools\Transform.exe
del Object\project.hex
