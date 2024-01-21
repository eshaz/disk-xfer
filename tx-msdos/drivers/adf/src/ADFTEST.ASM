;
; adftest.asm   January 19, 2000
;
; Copyright (c) 1995-2000 Scandinavian Digital Systems AB
;

                INCLUDE <adf.inc>

EXE             GROUP PROG, DATA, STACK

                ASSUME DS:EXE, ES:EXE, SS:EXE

PROG            SEGMENT PARA PUBLIC 'CODE'

txt_doc_init    DB 13,10
                DB 'AnDan Software ADFTest Version ',VERSION,13,10
                DB 'Copyright (c) 1995-2000 Scandinavian Digital Systems AB',13,10
                DB 13,10
                DB 'Internet: http://www.digsys.se     e-mail: andan@digsys.se',13,10
                DB 13,10
                DB 'Freeware: May be used, copied and distributed if no fee is',13,10
                DB '          charged and if no changes are done.',13,10
                DB 0

txt_doc_usage   DB 13,10
                DB 'adftest port',13,10
                DB 13,10
                DB 'port    FOSSIL port number, 0-126, or COM-port, COM1-COM127. Example: 0 or COM1',13,10
                DB 13,10
                DB 'ADFTest is a FOSSIL test program.',13,10
                DB 13,10
                DB 'ADFTest will send "ATE1<cr>" to the port and expect at least one character as',13,10
                DB 'reply. A modem connected to the port will in most cases do the job.',13,10
                DB 13,10
                DB 'ADFTest is intended to be used with ADFDebug for testing and verifying',13,10
                DB 'FOSSIL drivers.'
txt_nl          DB 13,10,0

err_arg         DB 13,10,'Argument error.',13,10,0

err_fossil      DB 13,10,'FOSSIL error (unable to open FOSSIL).',13,10,0

;                   1234567890123456789012345678901234567890
txt_test        DB 'ATE1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1E1',13
len_test        EQU $-txt_test

                ALIGN 2

port            DW 0

                ALIGN 4

;
; read_55ms
;
; In:  DS = CS
; Out: DX:AX = Value of the free running 55 ms counter
;
; Registers destroyed: BX,CX
;
; Each time unit is exactly:
;
; 65536/(14318180/12) s = 54.9254 ms
;
; This function uses the BIOS Timer Tick counter at 40H:6CH, and assumes
; that no program (except BIOS INT 08H) writes to the counter.
;
; It will handle the resetting of the counter done once a day by BIOS INT 08H.
;
; This function will also work in a multitasking environment,
; such as Windows or OS/2.
;

last_low        DW 0    ;last time, low word
last_high       DW 0    ;last time, high word
count_55ms_l    DW 0    ;55ms counter, low word
count_55ms_h    DW 0    ;55ms counter, high word

read_55ms:      pushf
                cli
                push ds
                xor ax,ax
                mov ds,ax
                mov ax,ds:[046CH]
                mov dx,ds:[046EH]
                pop ds
                mov bx,ax
                mov cx,dx
                sub ax,[last_low]
                sbb dx,[last_high]
                jnb read_55ms1
                add ax,000B0H
                adc dx,00018H
read_55ms1:     mov [last_low],bx
                mov [last_high],cx
                add ax,[count_55ms_l]
                adc dx,[count_55ms_h]
                mov [count_55ms_l],ax
                mov [count_55ms_h],dx
                popf
                ret

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

JobPrint:       pop si          ;NOTE! String at return address
                sti
                cld
                mov ax,cs
                mov ds,ax
                mov es,ax
                xor al,al
                mov di,si
                mov cx,0FFFFH
                repne scasb
                push di
                not cx
                dec cx
                mov bx,1
                mov dx,si
                mov ah,40H
                int 21H

AfterPrint:     call read_55ms
                mov di,ax
AfterPrint1:    call read_55ms
                sub ax,di
                cmp ax,9
                jb AfterPrint1
                xor ax,ax
                xor bx,bx
                xor cx,cx
                xor di,di
                xor si,si
                xor bp,bp
                mov dx,[port]
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
                sti
                cld
                mov ax,cs
                mov ds,ax
                mov es,ax
                mov si,OFFSET err_fossil
                jmp print_quit

Job             MACRO string:REQ
                call JobPrint
                DB 13,10,13,10
                DB string
                DB 13,10,0
                ENDM

adftest:        Job 'Activate port'
                mov ah,4
                int 14H
                cmp ax,1954H
                jnz fossil_err
                cmp bh,5
                jb fossil_err
                cmp bl,1BH
                jb fossil_err

                Job 'Set baud and parameters'
                mov ax,10100011B
                int 14H

                Job 'Set flow control'
                mov ax,0F02H
                int 14H

                Job 'Send AT<cr> (funcion 01H)'
                mov ax,0100H+'A'
                int 14H
                mov ax,0100H+'T'
                int 14H
                mov ax,0100H+13
                int 14H

                Job 'Get status'
                mov ah,03H
                int 14H

                Job 'Receive (funcion 02H).'
                mov ah,02H
                int 14H

                Job 'Send ATE1<cr> (funcion 0BH)'
                mov ax,0B00H+'A'
                int 14H
                mov ax,0B00H+'T'
                int 14H
                mov ax,0B00H+'E'
                int 14H
                mov ax,0B00H+'1'
                int 14H
                mov ax,0B00H+13
                int 14H

                Job 'Non-destructive read-ahead'
                mov ah,0CH
                int 14H

                Job 'Purge input buffer.'
                mov ah,0AH
                int 14H

                IF 0

                Job 'Get status'
                mov ah,03H
                int 14H

                ENDIF

                Job 'Get timer tick info'
                mov ah,07H
                int 14H

                Job 'Flush output buffer'
                mov ah,08H
                int 14H

                Job 'Purge output buffer'
                mov ah,09H
                int 14H

                Job 'Block write'
                mov di,OFFSET txt_test
                mov cx,len_test
                mov ah,19H
                int 14H

                Job 'Block read'
                mov di,OFFSET arg_buf
                mov cx,128
                mov ah,18H
                int 14H

                Job 'Lower DTR'
                mov ax,0600H
                int 14H

                Job 'Deactivate port'
                mov ah,5
                int 14H

                sti
                cld
                mov ax,cs
                mov ds,ax
                mov es,ax
                xor al,al
                jmp prg_exit

PROG            ENDS

DATA            SEGMENT PARA PUBLIC 'DATA'

arg_buf         DB 128 DUP(?)

DATA            ENDS

STACK           SEGMENT PARA STACK 'STACK'

                DB 2048 DUP(?)

STACK           ENDS

                END main
