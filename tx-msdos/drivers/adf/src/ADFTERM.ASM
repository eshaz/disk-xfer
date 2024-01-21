;
; adfterm.asm   January 19, 2000
;
; Copyright (c) 1995-2000 Scandinavian Digital Systems AB
;

                INCLUDE <adf.inc>

F1              EQU 3B00H
F2              EQU 3C00H
F3              EQU 3D00H
F4              EQU 3E00H
F5              EQU 3F00H
F6              EQU 4000H
F7              EQU 4100H
F8              EQU 4200H
F9              EQU 4300H
F10             EQU 4400H
SHIFT_F1        EQU 5400H
SHIFT_F2        EQU 5500H
SHIFT_F3        EQU 5600H
SHIFT_F4        EQU 5700H
SHIFT_F5        EQU 5800H
SHIFT_F6        EQU 5900H
SHIFT_F7        EQU 5A00H
SHIFT_F8        EQU 5B00H
SHIFT_F9        EQU 5C00H
SHIFT_F10       EQU 5D00H
CTRL_F1         EQU 5E00H
CTRL_F2         EQU 5F00H
CTRL_F3         EQU 6000H
CTRL_F4         EQU 6100H
CTRL_F5         EQU 6200H
CTRL_F6         EQU 6300H
CTRL_F7         EQU 6400H
CTRL_F8         EQU 6500H
CTRL_F9         EQU 6600H
CTRL_F10        EQU 6700H
ALT_F1          EQU 6800H
ALT_F2          EQU 6900H
ALT_F3          EQU 6A00H
ALT_F4          EQU 6B00H
ALT_F5          EQU 6C00H
ALT_F6          EQU 6D00H
ALT_F7          EQU 6E00H
ALT_F8          EQU 6F00H
ALT_F9          EQU 7000H
ALT_F10         EQU 7100H

EXE             GROUP PROG, DATA, STACK

                ASSUME DS:EXE, ES:EXE, SS:EXE

PROG            SEGMENT PARA PUBLIC 'CODE'


txt_doc_init    DB 13,10
                DB 'AnDan Software ADFTerm Version ',VERSION,13,10
                DB 'Copyright (c) 1995-2000 Scandinavian Digital Systems AB',13,10
                DB 13,10
                DB 'Internet: http://www.digsys.se     e-mail: andan@digsys.se',13,10
                DB 13,10
                DB 'Freeware: May be used, copied and distributed if no fee is',13,10
                DB '          charged and if no changes are done.',13,10
txt_null        DB 0


txt_doc_usage   DB 13,10
                DB 'adfterm port',13,10
                DB 13,10
                DB 'port    FOSSIL port number, 0-126, or COM-port, COM1-COM127. Example: 0 or COM1',13,10
                DB 13,10
                DB 'ADFTerm is a very small and simple communication program, that uses the ADF',13,10
                DB 'or any FOSSIL driver. It will set 2400 bps and 8N1 if FOSSIL is not locked.',13,10
                DB 13,10
                DB 'You may call BBSes and use ANSI-BBS if you have ANSI.SYS loaded.'
txt_nl          DB 13,10,0

err_arg         DB 13,10,'Argument error.',13,10,0

err_fossil      DB 13,10,'FOSSIL error (unable to open FOSSIL).',13,10,0

txt_open        DB 13,10,'Opening FOSSIL.',13,10,0

txt_hlp         DB 13,10,'Press F1 for help.',13,10,13,10,0

txt_F1          DB 13,10,13,10,'Special keys:',13,10,13,10
                DB 'F1  Help',13,10
                DB 'F2  Display status',13,10
                DB 'F3  Lower DTR',13,10
                DB 'F4  Raise DTR',13,10
                DB 'F5  Display FOSSIL info',13,10
                DB 'F6  Reserved',13,10
                DB 'F7  Reserved',13,10
                DB 'F8  Keep FOSSIL open and end program',13,10
                DB 'F9  Close FOSSIL and end program',13,10
                DB 'F10 Lower DTR, close and end program',13,10
                DB 13,10,0

txt_F2          DB 13,10
                DB 13,10
                DB 'Line status (AH)',13,10
                DB 13,10
                DB 'Bit 0, Input data in buffer (RDA):      '
valh0           DB 'x',13,10
                DB 'Bit 1, Input buffer overrun (OVRN):     '
valh1           DB 'x',13,10
                DB 'Bit 2, Parity error:                    '
valh2           DB 'x',13,10
                DB 'Bit 3, Framing error:                   '
valh3           DB 'x',13,10
                DB 'Bit 4, Break detect:                    '
valh4           DB 'x',13,10
                DB 'Bit 5, Room in output buffer (THRE):    '
valh5           DB 'x',13,10
                DB 'Bit 6, Output buffer is empty (TSRE):   '
valh6           DB 'x',13,10
                DB 'Bit 7, Timeout:                         '
valh7           DB 'x',13,10
                DB 13,10
                DB 'Modem status (AL)',13,10
                DB 13,10
                DB 'Bit 0, Delta clear to send:             '
vall0           DB 'x',13,10
                DB 'Bit 1, Delta data set ready:            '
vall1           DB 'x',13,10
                DB 'Bit 2, Delta data carrier detect:       '
vall2           DB 'x',13,10
                DB 'Bit 3, Always set to 1:                 '
vall3           DB 'x',13,10
                DB 'Bit 4, Clear to send (CTS):             '
vall4           DB 'x',13,10
                DB 'Bit 5, Data set ready (DSR):            '
vall5           DB 'x',13,10
                DB 'Bit 6, Ring indicator (RI):             '
vall6           DB 'x',13,10
                DB 'Bit 7, Data carrier detect (DCD):       '
vall7           DB 'x',13,10
                DB 13,10,0

txt_F3          DB 13,10,'Lowering DTR.',13,10,0

txt_F4          DB 13,10,'Raising DTR.',13,10,0

txt_F9          DB 13,10,'Closing FOSSIL.',13,10,0

txt_F8          DB 13,10,'Terminating.',13,10,13,10,0

txt_F5a         DB 13,10,13,10,'FOSSIL info:',13,10,13,10
                DB 'Size of structure:  '
val_strsiz      DB 'xxxxx',13,10
                DB 'Major version:      '
val_majver      DB 'xxxxx',13,10
                DB 'Minor version:      '
val_minver      DB 'xxxxx',13,10
                DB 'ID string:          ',0

txt_F5b         DB 13,10
                DB 'Size rec buffer:    '
val_ibufr       DB 'xxxxx',13,10
                DB 'Free rec buffer:    '
val_ifree       DB 'xxxxx',13,10
                DB 'Size tra buffer:    '
val_obufr       DB 'xxxxx',13,10
                DB 'Free tra buffer:    '
val_ofree       DB 'xxxxx',13,10
                DB 'Width of screen:    '
val_swidth      DB 'xxxxx',13,10
                DB 'Height of screen:   '
val_sheight     DB 'xxxxx',13,10
                DB 'Baud rate code:     '
val_baud        DB 'xxxxx',13,10,0

                ALIGN 2

port            DW 0

info_struct     EQU $
info_strsiz     DW 0                    ;Size of the structure in bytes
info_majver     DB 0                    ;FOSSIL spec driver conforms to
info_minver     DB 0                    ;Rev level of this specific driver
info_ident      DD 0                    ;"FAR" pointer to ASCII ID string
info_ibufr      DW 0                    ;Size of the input buffer (bytes)
info_ifree      DW 0                    ;Number of bytes left in buffer
info_obufr      DW 0                    ;Size of the output buffer (bytes)
info_ofree      DW 0                    ;Number of bytes left in the buffer
info_swidth     DB 0                    ;Width of screen on this adapter
info_sheight    DB 0                    ;Height of screen on this adapter
info_baud       DB 0                    ;Actual baud rate, computer to modem
info_size       EQU $-info_struct

                ALIGN 4

utoa_tab        DW 10000
                DW 1000
                DW 100
                DW 10
                DW 1
;
; utoa
;
; In:  AX = 16 bit unsigned integer
;      ES:DI = Buffer
;
utoa:           push si
                mov cx,5*256+' '
                mov si,OFFSET utoa_tab
                mov dx,ax
utoa1:          mov ax,dx
                xor dx,dx
                div WORD PTR [si]
                inc si
                inc si
                and al,al
                jz utoa4
utoa2:          mov cl,'0'
utoa3:          or al,cl
                stosb
                dec ch
                jnz utoa1
                pop si
                ret

utoa4:          cmp ch,1
                jz utoa2
                jmp utoa3

                ALIGN 2

print:          xor al,al
                mov di,si
                mov cx,0FFFFH
                repne scasb
                not cx
                dec cx
                mov bx,1
                mov dx,si
                mov ah,40H
                int 21H
                ret

                ALIGN 2

jmp_white:      lodsb
                cmp al,13
                je jmp_white1
                cmp al,32
                jbe jmp_white
                dec si
                clc
                ret
jmp_white1:     dec si
                stc
                ret

                ALIGN 2

ascdec:         xor ax,ax
                xor cx,cx
                mov bx,10
ascdec1:        mov cl,[si]
                sub cl,'0'
                jc ascdec3
                cmp cl,bl
                jae ascdec3
                inc si
                mul bx
                and dx,dx
                jnz ascdec2
                add ax,cx
                jnc ascdec1
ascdec2:        stc
                ret
ascdec3:        cmp BYTE PTR [si],33
                cmc
                ret

                ALIGN 2

;
; Start of program
;
main:           cld
                mov dx,cs               ;DX=EXE segment
                mov ax,ss               ;AX=STACK segment
                sub ax,dx               ;AX=distance between STACK and EXE
                mov cl,4
                shl ax,cl               ;Distance in bytes
                add ax,sp               ;SP should be added with the distance
                and ax,0FFF0H
                cli
                mov ss,dx
                mov sp,ax
                sti
                shr ax,cl
                add ax,dx               ;AX=First free segment
                mov ds:[2],ax
                mov bx,es
                sub bx,ax
                neg bx
                mov ah,4AH              ;Set memory block size
                int 21H
                mov es,dx
                mov si,80H
                mov di,OFFSET arg_buf
                mov cl,[si]
                add cl,3
                shr cl,1
                xor ch,ch
                rep movsw
                mov ds,dx

                mov si,OFFSET txt_doc_init
                call print

                mov si,OFFSET arg_buf+1
                call jmp_white
                jnc parse1

                mov si,OFFSET txt_doc_usage

print_quit:     mov al,0FFH

print_exit:     push ax
                call print
                pop ax

prg_exit:       mov ah,4CH
                int 21H

prg_quit:       mov al,0FFH
                jmp prg_exit

                ALIGN 2

parse1:         cmp al,'c'
                jz port11
                cmp al,'C'
                jnz port14
port11:         inc si
                lodsb
                cmp al,'o'
                jz port12
                cmp al,'O'
                jnz arg_err
port12:         lodsb
                cmp al,'m'
                jz port13
                cmp al,'M'
                jnz arg_err
port13:         call ascdec
                jc arg_err
                sub ax,1
                jae port15
                jmp arg_err

port14:         call ascdec
                jc arg_err
port15:         cmp ax,126
                ja arg_err
                mov [port],ax
                call jmp_white
                jc adftest

arg_err:        mov si,OFFSET err_arg
                jmp print_quit

fossil_err:     mov dx,[port]
                mov ah,5
                int 14H
                mov si,OFFSET err_fossil
                jmp print_quit

adftest:        mov si,OFFSET txt_open
                call print
                mov dx,[port]
                mov ah,4
                int 14H
                cmp ax,1954H
                jnz fossil_err
                cmp bh,5
                jb fossil_err
                cmp bl,21H
                jb fossil_err

                mov ax,10100011B
                int 14H

                mov ax,0F02H
                int 14H

                mov si,OFFSET txt_hlp
                call print

;
; Main loop
;
adf100:         mov ah,1
                int 16H
                jz adf102
                xor ah,ah
                int 16H
                cmp ax,F1
                jb adf101
                cmp ax,F10
                ja adf101
                mov bl,ah
                xor bh,bh
                sub bl,3BH
                shl bx,1
                call [func_table+bx]
                jmp adf100

adf101:         and al,al
                jz adf102

                mov dx,[port]
                mov ah,01H
                int 14H

adf102:         mov dx,[port]
                mov ah,03H
                int 14H
                test ah,00000001B
                jz adf100

adf103:         mov dx,[port]
                mov ah,02H
                int 14H
                mov bx,ax
                mov dl,al
                mov ah,2
                int 21H
                test bh,00000001B
                jnz adf103
                jmp adf100

                ALIGN 2

func_table      DW OFFSET funcF1
                DW OFFSET funcF2
                DW OFFSET funcF3
                DW OFFSET funcF4
                DW OFFSET funcF5
                DW OFFSET funcF6
                DW OFFSET funcF7
                DW OFFSET funcF8
                DW OFFSET funcF9
                DW OFFSET funcF10

funcF1:         mov si,OFFSET txt_F1
                call print
                ret

                ALIGN 2

binascnext:     mov al,cl
                shr ah,1
                adc al,ch
                mov [di],al
                ret

funcF2:         mov dx,[port]
                mov ah,03H
                int 14H
                push ax
                mov cx,'0'
                mov di,OFFSET valh0
                call binascnext
                mov di,OFFSET valh1
                call binascnext
                mov di,OFFSET valh2
                call binascnext
                mov di,OFFSET valh3
                call binascnext
                mov di,OFFSET valh4
                call binascnext
                mov di,OFFSET valh5
                call binascnext
                mov di,OFFSET valh6
                call binascnext
                mov di,OFFSET valh7
                call binascnext
                pop ax
                mov ah,al
                mov di,OFFSET vall0
                call binascnext
                mov di,OFFSET vall1
                call binascnext
                mov di,OFFSET vall2
                call binascnext
                mov di,OFFSET vall3
                call binascnext
                mov di,OFFSET vall4
                call binascnext
                mov di,OFFSET vall5
                call binascnext
                mov di,OFFSET vall6
                call binascnext
                mov di,OFFSET vall7
                call binascnext
                mov si,OFFSET txt_F2
                call print
                ret

funcF3:         mov si,OFFSET txt_F3
                call print
                mov dx,[port]
                mov ax,0600H
                int 14H
                ret

funcF4:         mov si,OFFSET txt_F4
                call print
                mov dx,[port]
                mov ax,0601H
                int 14H
                ret

funcF5:         mov WORD PTR [info_ident+0],bx
                mov WORD PTR [info_ident+2],cs
                mov cx,info_size
                mov di,OFFSET info_struct
                mov dx,[port]
                mov ah,1BH
                int 14H
                mov di,OFFSET val_strsiz
                mov ax,[info_strsiz]
                call utoa
                mov di,OFFSET val_majver
                xor ah,ah
                mov al,[info_majver]
                call utoa
                mov di,OFFSET val_minver
                xor ah,ah
                mov al,[info_minver]
                call utoa
                mov di,OFFSET val_ibufr
                mov ax,[info_ibufr]
                call utoa
                mov di,OFFSET val_ifree
                mov ax,[info_ifree]
                call utoa
                mov di,OFFSET val_obufr
                mov ax,[info_obufr]
                call utoa
                mov di,OFFSET val_ofree
                mov ax,[info_ofree]
                call utoa
                mov di,OFFSET val_swidth
                xor ah,ah
                mov al,[info_swidth]
                call utoa
                mov di,OFFSET val_sheight
                xor ah,ah
                mov al,[info_sheight]
                call utoa
                mov di,OFFSET val_baud
                xor ah,ah
                mov al,[info_baud]
                call utoa
                lds si,[info_ident]
                mov di,OFFSET arg_buf
funcF5a:        lodsb
                stosb
                and al,al
                jnz funcF5a
                mov ax,cs
                mov ds,ax
                mov si,OFFSET txt_F5a
                call print
                mov si,OFFSET arg_buf
                call print
                mov si,OFFSET txt_F5b
                call print
                ret

funcF6:
funcF7:
                ret

funcF10:        call funcF3

funcF9:         mov si,OFFSET txt_F9
                call print
                mov dx,[port]
                mov ah,5
                int 14H

funcF8:         mov si,OFFSET txt_F8
                xor al,al
                jmp print_exit

PROG            ENDS

DATA            SEGMENT PARA PUBLIC 'DATA'

arg_buf         DB 128 DUP(?)

DATA            ENDS

STACK           SEGMENT PARA STACK 'STACK'

                DB 2048 DUP(?)

STACK           ENDS

                END main
