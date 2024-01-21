@echo off
rem
rem Loading ADF for COM1
rem
rem    �������������������������������COM-port number, COM1-COM127.
rem    �   ���������������������������Address in hex of COM-port, 0-FFFF.
rem    �   �  ������������������������IRQ number of COM-port, 0-15.
rem    �   �  �      �����������������Locked baud-rate, 1-115200.
rem    �   �  �      �     �����������Size of receive buffer, 256-16384.
rem    �   �  �      �     �     �����Size of transmit buffer, 256-16384.
rem    �   �  �      �     �     �  ��Receiver FIFO trigger level, 1, 4, 8, 14.
rem    �   �  �      �     �     �  �
adf COM1 3F8  4 115200  1024  1024  8
rem                        �        �
rem    ���������������������        �
rem    �               ��������������   Advanced options:
rem    �               �
rem 8192,7168,6144 16650,16,8    3  11
rem         �    �        � �    �   �
rem         �    �        � �    �   �� Modem Control Register.
rem         �    �        � �    ������ Line Control Register.
rem         �    �        � ����������� 16650 Transmit FIFO trigger level:
rem         �    �        �             8, 16, 24 or 30.
rem         �    �        ������������� 16650 Receive FIFO trigger level:
rem         �    �                      8, 16, 24 or 28.
rem         �    ���������������������� Flow control continue or restart.
rem         ��������������������������� Flow control hold or stop.
rem
