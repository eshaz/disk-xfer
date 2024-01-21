;
; adfcomch.asm  January 19, 2000
;
; Copyright (c) 1995-2000 Scandinavian Digital Systems AB
;

                INCLUDE <adf.inc>

EXE             GROUP PROG, DATA, STACK

                ASSUME DS:EXE, ES:EXE, SS:EXE

PROG            SEGMENT PARA PUBLIC 'CODE'


txt_doc_init    DB 13,10
                DB 'AnDan Software ADFComCh Version ',VERSION,13,10
                DB 'Copyright (c) 1995-2000 Scandinavian Digital Systems AB',13,10
                DB 13,10
                DB 'Internet: http://www.digsys.se     e-mail: andan@digsys.se',13,10
                DB 13,10
                DB 'Freeware: May be used, copied and distributed if no fee is',13,10
                DB '          charged and if no changes are done.',13,10
                DB 0

txt_doc_usage   DB 13,10
                DB 'adfcomch addr',13,10
                DB 13,10
                DB 'addr    Address in hex of COM port, 0-FFFF. Example: 3F8',13,10
                DB 13,10
                DB 'ADFComCh checks if there is an UART at the specified port address. The most',13,10
                DB 'common port addresses are:',13,10
                DB 13,10
                DB '    COM1    3F8',13,10
                DB '    COM2    2F8',13,10
                DB '    COM3    3E8',13,10
                DB '    COM4    2E8',13,10
                DB 13,10
                DB 'The current UART settings will be cleared or modified. Please run from plain',13,10
                DB 'DOS only, and reboot or load ADF after usage. Sets ERRORLEVEL to:',13,10
                DB 13,10
                DB '255  Error',13,10
                DB '  5  No UART',13,10
                DB '  4  16450',13,10
                DB '  3  16550',13,10
                DB '  2  16650',13,10
                DB '  1  16750'
txt_nl          DB 13,10,0

err_arg         DB 13,10,'Argument error.',13,10,0

txt_16750OK     DB 13,10,'The UART is a 16750 or compatible.',13,10,0

txt_16650OK     DB 13,10,'The UART is a 16650 or compatible.',13,10,0

txt_16550OK     DB 13,10,'The UART is a 16550 or compatible.',13,10,0

txt_16550BAD    DB 13,10,'There seems to be an UART, but not a 16550, 16650 or 16750.',13,10,0

txt_no_UART     DB 13,10,'There is no UART.',13,10,0

                ALIGN 2

port            DW 0

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

aschex:         xor ax,ax
                xor cx,cx
                mov bx,10h
aschex1:        mov cl,[si]
                sub cl,'0'
                jc aschex4
                cmp cl,10
                jae aschex5
aschex2:        inc si
                mul bx
                and dx,dx
                jnz aschex3
                add ax,cx
                jnc aschex1
aschex3:        stc
                ret
aschex4:        cmp BYTE PTR [si],33
                cmc
                ret
aschex5:        sub cl,7
                jc aschex4
                cmp cl,16
                jb aschex2
                sub cl,32
                cmp cl,16
                jb aschex2
                jmp aschex4

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

parse1:         call aschex
                jc arg_err
                mov [port],ax
                call jmp_white
                jc comcheck

arg_err:        mov si,OFFSET err_arg
                jmp print_quit

comcheck:       mov dx,[port]           ;Base address
                cli
                add dx,3                ;Base+3
                mov al,10111111B        ;Access Enhanced Feature Register
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                mov al,00010000B        ;Enable Enhanced Feature Register
                out dx,al
                jmp $+2
                inc dx                  ;Base+3
                mov al,00000011B        ;DLAB=0
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                xor al,al               ;Disables FIFO
                out dx,al
                jmp $+2
                dec dx                  ;Base+1
                xor al,al               ;Disable interrupts
                out dx,al
                jmp $+2
                jmp $+2
                out dx,al
                add dx,3                ;Base+4, modem control register
                xor al,al
                out dx,al
                jmp $+2
                jmp $+2
                in al,dx                ;Modem Control Register
                jmp $+2
                and al,al
                jz comcheck10

to_comcheck4:   jmp comcheck4           ;No UART

comcheck10:     dec dx                  ;Base+3
                in al,dx                ;Line Control Register
                jmp $+2
                cmp al,00000011B        ;DLAB=0
                jnz to_comcheck4        ;No UART
                dec dx                  ;Base+2
                dec dx                  ;Base+1
                in al,dx                ;Interrupt Enable Register
                jmp $+2
                and al,al
                jnz to_comcheck4        ;No UART
                inc dx                  ;Base+2
                mov al,10000111B        ;16550 FIFO Enable
                out dx,al               ;FIFO control register
                jmp $+2
                jmp $+2
                in al,dx                ;Interrupt Identification Register
                and al,11000000B        ;Check bit 6-7
                cmp al,11000000B        ;Is FIFOs Enabled?
                jz comcheck11

                jmp comcheck3           ;No, it is not a 16550/16650

comcheck11:     inc dx                  ;Base+3
                inc dx                  ;Base+4, modem control register
                mov al,11111111B
                out dx,al
                jmp $+2
                jmp $+2
                in al,dx                ;Modem Control Register
                jmp $+2
                jmp $+2
                mov ah,al               ;Save it
                xor al,al
                out dx,al
                jmp $+2
                dec dx                  ;Base+3

                inc ah
                jz comcheck1

                mov al,10000011B        ;DLAB=1
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                mov al,10100111B        ;16750 FIFO Enable
                out dx,al               ;FIFO control register
                jmp $+2
                inc dx                  ;Base+3
                mov al,00000011B        ;DLAB=0
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                in al,dx                ;Interrupt Identification Register
                mov ah,al               ;Save it
                dec dx                  ;Base+3
                mov al,10000011B        ;DLAB=1
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                xor al,al
                out dx,al               ;FIFO control register
                jmp $+2
                inc dx                  ;Base+3
                mov al,00000011B        ;DLAB=0
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                xor al,al               ;Disables FIFO
                out dx,al
                jmp $+2
                and ah,11100000B        ;Check bit 6-7
                cmp ah,11100000B        ;Is FIFOs Enabled?
                jnz comcheck2           ;No, it is not a 16750

                sti
                mov si,OFFSET txt_16750OK
                mov al,1
                jmp print_exit

comcheck1:      dec dx                  ;Base+3
                mov al,10111111B        ;Access Enhanced Feature Register
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                xor al,al               ;Disable Enhanced Feature Register
                out dx,al
                jmp $+2
                inc dx                  ;Base+3
                mov al,00000011B        ;DLAB=0
                out dx,al
                jmp $+2
                dec dx                  ;Base+2
                xor al,al               ;Disables FIFO
                out dx,al
                sti
                mov si,OFFSET txt_16650OK
                mov al,2
                jmp print_exit

comcheck2:      sti
                mov si,OFFSET txt_16550OK
                mov al,3
                jmp print_exit

comcheck3:      sti
                mov si,OFFSET txt_16550BAD
                mov al,4
                jmp print_exit

comcheck4:      sti
                mov si,OFFSET txt_no_UART
                mov al,5
                jmp print_exit

PROG            ENDS

DATA            SEGMENT PARA PUBLIC 'DATA'

arg_buf         DB 128 DUP(?)

DATA            ENDS

STACK           SEGMENT PARA STACK 'STACK'

                DB 2048 DUP(?)

STACK           ENDS

                END main
