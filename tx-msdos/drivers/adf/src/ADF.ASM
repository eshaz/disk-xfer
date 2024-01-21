;
; adf.asm       January 19, 2000
;
; Copyright (c) 1994-2000 Scandinavian Digital Systems AB
;
;
; Note, MASM v6.11 cannot use "ASSUME CS:", and OFFSET always gives the
; offset to the label's segment or group, no segment override is available.
; This makes it hard to write efficient TSR COM-programs, so this program
; is an EXE-program.
;

                INCLUDE <adf.inc>

EXE             GROUP PROG, DATA, STACK

                ASSUME DS:EXE, ES:EXE, SS:EXE

;
; FOSSIL
;

INT14_MAXFUNC   EQU 21H
INT14_REV       EQU 5
POLL_MOD_STAT   EQU 1           ;EQU 0 not checked since reconstruction of lost source code
USE_TIMER       EQU 1           ;=0 --> do not use timers (for test purposes)
LOCK_MOD_CTRL   EQU 1           ;Lock Modem Control Register

TIMER_INT       EQU 08H

RESET_PC        SEGMENT AT 0FFFFH

                ORG 00000H

start_pc        LABEL FAR       ;Address to the reset routine on PC

RESET_PC        ENDS

RESET_AT        SEGMENT AT 0F000H

                ORG 0FFF0H

start_at        LABEL FAR       ;Address to the reset routine on AT

RESET_AT        ENDS

PROG            SEGMENT PARA PUBLIC 'CODE'

; The TSR starts at offset 0

tsr_id          DB 0,13

info_string     DB 'AnDan Software FOSSIL Version ',VERSION
                DB 0

tsr_id_len      EQU $-tsr_id

                ALIGN 2

;
; Data set by main program
;
fossil_port     DB 0 ;FOSSIL port number, 0-126
com_irq         DB 0 ;IRQ number of COM-port, 0-15
com_base        DW 0 ;Base address of COM-port
com_config      DB 0 ;Config bits
; Bit:  Meaning:
;
;  0    =1 --> Enable carrier watchdog
;  1    =1 --> Enable 16650
;  2    =1 --> Enable 16750
; 3-7   Reserved
com_fifoctrl    DB 0 ;FIFO control register (bit 2-0 must be zero)
com_linectrl    DB 0 ;Line control register (bit 7-6 must be zero)
com_modemctrl   DB 0 ;Modem control register
com_trafifo1    DB 0 ;Bytes to fill FIFO on transmit hold register empty
com_trafifo2    DB 0 ;Bytes to fill FIFO on transmit interrupt
com_enhanced    LABEL WORD
com_accenh      DB 0 ;LCR to Access Enhanced Feature Register
com_enhreg      DB 0 ;Enhanced Feature Register
com_baud        DW 0 ;Locked baud code
com_recstart    DW 0 ;Start of receiver buffer
com_recend      DW 0 ;End of receiver buffer
com_reclim      LABEL WORD ;End of receiver buffer plus one (=com_trastart)
com_trastart    DW 0 ;Start of transmitter buffer
com_traend      DW 0 ;End of transmitter buffer
com_tralim      DW 0 ;End of transmitter buffer plus one (= first free byte of program)
com_reclen      DW 0 ;Size of receive buffer = [com_recend]-[com_recstart]+1
com_tralen      DW 0 ;Size of transmit buffer = [com_traend]-[com_trastart]+1
com_recflhold   DW 0 ;Flow trigger hold
com_recflcont   DW 0 ;Flow trigger continue
com_picmsk1     DW 0 ;PIC #1 mask
com_picmsk2     DW 0 ;PIC #2 mask, or zero
;
; Info structure
;
info_struct     EQU $
info_strsiz     DW info_size            ;Size of the structure in bytes
info_majver     DB INT14_REV            ;FOSSIL spec driver conforms to
info_minver     DB 0                    ;Rev level of this specific driver
info_ident_o    DW OFFSET info_string   ;"FAR" pointer to ASCII ID string
info_ident_s    DW 0
info_ibufr      DW 0                    ;Size of the input buffer (bytes)
info_ifree      DW 0                    ;Number of bytes left in buffer
info_obufr      DW 0                    ;Size of the output buffer (bytes)
info_ofree      DW 0                    ;Number of bytes left in the buffer
info_swidth     DB 0                    ;Width of screen on this adapter
info_sheight    DB 0                    ;Height of screen on this adapter
info_baud       DB 00100011B            ;Actual baud rate, computer to modem
info_size       EQU $-info_struct

;
; Private data
;
com_status      DB 0 ;Statusbits:
; Bit:  Meaning:
;
;  0    =1 --> Ctrl-C or Ctrl-K recevied
;  1    =1 --> Receive buffer full error
;  2    =1 --> Enable Ctrl-C and Ctrl-K check
;  3
;  4    =1 --> RTS deactivated
;  5
;  6
;  7    =1 --> Transmitter disabled
com_line        DB 0 ;Line status:
; Bit:  Meaning:
;
;  0   Data Ready, DR
;      Data exists in the Receiver Buffer Register
;  1   Overrun Error, OE
;  2   Parity Error, PE
;  3   Framing Error, FE
;  4   Break Interrupt, BI
;  5   Transmitter Holding Register Empty, THRE
;  6   Transmitter Empty, TEMT
;  7   Error in RCVR FIFO

                IFE POLL_MOD_STAT

com_modem       DB 0 ;Modem status:
; Bit:  Meaning:
;
;  0    CTS changed
;  1    DSR changed
;  2    RI changed to active
;  3    DCD changed
;  4    CTS
;  5    DSR
;  6    RI
;  7    DCD

                DB 0 ;Reserved

                ENDIF

com_picval1     DB 0 ;Old PIC #1 enable bit
com_picval2     DB 0 ;Old PIC #2 enable bit
com_rec         DW 0 ;Current rec position
com_tra         DW 0 ;Current tra position
com_recint      DW 0 ;Interrupt's current pos
com_traint      DW 0 ;Interrupt's current pos

timer_doing     DB 0 ;TIMER_INT in process
                DB 0 ;Reserved
timer_watchini  DW 0 ;Carrier watchdog initialization
timer_watchcnt  DW 0 ;Carrier watchdog counter
timer_last_l    DW 0 ;Last time, low 16
timer_last_h    DW 0 ;Last time, high 16

NUM_TIMERS      EQU 4

timer_calls     DD NUM_TIMERS DUP(0)

                ALIGN 4

;
; uart_poll
;
; In:  DX = Base address
; Out: CLI has been done
;
; Destroyed registers: AX, BX, CX
;

uart_poll1:     or [com_line],al
                sub dx,5                ;Base+0
                in al,dx                ;Receiver Data Register

                ALIGN 4

uart_poll:      sti
                inc dx                          ;Base+1
                inc dx                          ;Base+2
                in al,dx                        ;Interrupt Identification Register
;;;             jmp $+2
                mov cl,al
                add dx,3                        ;Base+5
                cli
                in al,dx                        ;Line Status Register
                test al,00011110B               ;Error?
                jnz uart_poll1
                test al,00000001B               ;Characters in receiver FIFO
                jnz uart_poll2
                test al,00100000B               ;Transmit FIFO empty
                jnz transmit1
transmit_ret2:  sub dx,5                        ;Base+0
                ret

                ALIGN 4

uart_poll2:     sub dx,5                        ;Base+0
                call receive
                jmp uart_poll

                ALIGN 4

;
; transmit1 and transmit2
;
; In:  DX = Base address + 5
;      CL = Interrupt Identification Register
;      CLI must have been done, or must be called from interrupt routine
; Out: CH = 0
;
transmit1:      mov ah,[com_trafifo1]   ;Bytes to fill FIFO on transmit hold register empty
transmit2:      xor ch,ch
                test [com_status],10000000B     ;Transmitter disabled?
                jnz transmit_ret2               ;Yes, return
                mov bx,[com_traint]
                cmp bx,[com_tra]
                jz transmit_ret2                ;Return
                IF POLL_MOD_STAT
                inc dx                          ;Base+6
                in al,dx                        ;Modem Status Register
                sub dx,6                        ;Base+0
                test al,00010000B               ;CTS
                ELSE
                sub dx,5                        ;Base+0
                test [com_modem],00010000B      ;CTS
                ENDIF
                jz transmit_ret                 ;Return
                and cl,11000000B
                xor cl,11000000B
                mov cl,1
                jnz transmit11
                mov cl,ah

                ALIGN 4

transmit11:     mov al,[bx]
                out dx,al                       ;Transmitter Holding Register
                cmp bx,[com_traend]
                jz transmit13
                inc bx
transmit12:     cmp bx,[com_tra]
                loopnz transmit11
                mov [com_traint],bx
transmit_ret:   ret

                ALIGN 4

transmit13:     mov bx,[com_trastart]
                jmp transmit12

                ALIGN 4

;
; receive
;
; In:  DX = Base address
;      CLI must have been done, or must be called from interrupt routine
;
receive:        in al,dx                        ;Receiver Data Register
receive_poke:   test [com_status],00000100B     ;Enable Ctrl-C and Ctrl-K check
                jnz receive30                   ;Yes
receive1:       mov bx,[com_recint]
                mov [bx],al
                cmp bx,[com_recend]
                jz receive4
                inc bx
receive2:       mov [com_recint],bx
                sub bx,[com_rec]
                jz receive10
                jnc receive3
                add bx,[com_reclen]
receive3:       cmp bx,[com_recflhold]
                jae receive20
                ret

                ALIGN 4

receive4:       mov bx,[com_recstart]
                jmp receive2

                ALIGN 4

receive10:      mov bx,[com_rec]
                cmp bx,[com_recend]
                jnz receive11
                mov bx,[com_recstart]
                dec bx
receive11:      inc bx
                mov [com_rec],bx
                or [com_status],00000010B        ;Receive buffer full error

                ALIGN 4

receive20:      or [com_status],00010000B        ;RTS
                add dx,4        ;Base+4, modem control register
                pushf
                cli
                in al,dx
                jmp $+2
                and al,11111101B        ;RTS off
                out dx,al
                popf
                sub dx,4        ;Base+0
                ret

                ALIGN 4

receive30:      cmp al,'C'-64   ;Ctrl-C
                jz receive31
                cmp al,'K'-64   ;Ctrl-K
                jnz receive1
receive31:      or [com_status],00000001B       ;Ctrl-C or Ctrl-K received
                ret

;
; Communication Interrupt Handler
;

                ALIGN 4

                DD 0
                DB 00H,'INT'

comint:         sti
                push ax
                push bx
                push cx
                push dx
                push ds

                mov ax,cs
                mov ds,ax
                mov ch,1        ;Zero if 'int_tra' has been processed last
                mov dx,[com_base]

                ALIGN 4

again:          inc dx
                inc dx                  ;Base+2
                in al,dx                ;Interrupt Identification Register
                mov cl,al               ;Used by 'transmit'
                shr al,1
                jc int_poll

                mov ch,1        ;Zero if 'int_tra' has been processed last
                and al,00000011B
                jz int_mod
                dec al
                jz int_tra
                dec al
                jz int_rec

                add dx,3                ;Base+5
                in al,dx                ;Line Status Register
                jmp $+2
int_lin1:       or [com_line],al
                sub dx,5                ;Base+0
                in al,dx                ;Receiver Data Register
                jmp again

                ALIGN 4

int_poll:       add dx,3                ;Base+5
                in al,dx                ;Line Status Register
                test al,00011110B       ;Error?
                jnz int_lin1
                test al,00000001B
                jnz int_rec1
                test al,00100000B
                jz int_end
                and ch,ch       ;Zero if 'transmit' has been processed last
                jz int_end
                call transmit1

int_end:        mov al,20H
                cmp [com_irq],8
                cli
                jb int_end1
                out 0A0H,al
                jmp $+2
int_end1:       out 020H,al
                pop ds
                pop dx
                pop cx
                pop bx
                pop ax
                iret

                ALIGN 4

int_rec1:       sub dx,5                ;Base+0
                call receive
                jmp again

                ALIGN 4

int_tra:        add dx,3                ;Base+5
                mov ah,[com_trafifo2]   ;Bytes to fill FIFO on transmit interrupt
                call transmit2
                jmp again

                ALIGN 4

int_rec:        dec dx
                dec dx                  ;Base+0
                call receive
                jmp again

                ALIGN 4

int_mod:        add dx,4                ;Base+6
                in al,dx                ;Modem Status Register
                IFE POLL_MOD_STAT
                mov [com_modem],al
                ENDIF
                sub dx,6                ;Base+0
                jmp again

                ALIGN 4

;
; cgetcomsub2
;
; In:   DX = Base address
;       BX = [com_rec]
;       CLI must have been done
;
; Out:  [com_rec] incremented
;       STI has been done
;
; Destroyed registers: CX
;

cgetcomsub1:    mov bx,[com_recstart]
                jmp cgetcomsub3

                ALIGN 4

cgetcomsub2:    cmp bx,[com_recend]
                jz cgetcomsub1
                inc bx

cgetcomsub3:    mov [com_rec],bx
                test [com_status],00010000B        ;RTS
                jnz rts_release1
                sti
                ret

                ALIGN 4

;
; rts_release1
;
; In:   DX = Base address
;       BX = [com_rec]
;       [com_status] = Bit 00010000B must be set
;       CLI must have been done
;
; Out:  STI has been done
;
; Destroyed registers: AL, CX
;

rts_release1:   mov cx,[com_recint]
                sub cx,bx
                jnc rts_release2
                add cx,[com_reclen]
rts_release2:   cmp cx,[com_recflcont]
                jb rts_release3
                sti
                ret

                ALIGN 4

;
; rts_release3
;
; In:   DX = Base address
;       CLI must have been done
;
; Out:  [com_status] = Bit 00010000B will be cleared
;       STI has been done
;
; Destroyed registers: AL, CX
;

rts_release3:   and [com_status],11101111B      ;RTS
                add dx,4        ;Base+4, modem control register
                mov cl,al
                in al,dx
                jmp $+2
                or al,00000010B ;RTS on
                out dx,al
                mov al,cl
                sub dx,4
                sti
                ret

                ALIGN 4

;
; cputcomsub1
;
;
; In:   ----
;
; Out:  CF = 1 --> No space
;                  AX = 0
;       CF = 0 --> Space
;                  AX = 1
;                  DS:BX = Empty space in transmit buffer
;                  DS:CX = One character ahead
;                  CLI has been done
;
cputcomsub1:    cli
                mov bx,[com_tra]
                mov cx,bx
                cmp cx,[com_traend]
                jz cputcomsub13
                inc cx
cputcomsub11:   cmp cx,[com_traint]
                jz cputcomsub12
                clc
                ret

                ALIGN 4

cputcomsub12:   sti
                stc
                ret

                ALIGN 4

cputcomsub13:   mov cx,[com_trastart]
                jmp cputcomsub11

                ALIGN 4

;
; get_status
;
; In:  DX = Base address
; Out: AX = Status
;      STI has been done
;
; Destroyed registers: BX, CX, DX
;
get_status:     call uart_poll
                IF POLL_MOD_STAT
                add dx,6                        ;Base+6
                in al,dx                        ;Modem Status Register
                sub dx,6                        ;Base+0
                ELSE
                mov al,[com_modem]
                ENDIF
                xor ah,ah
                xchg ah,[com_line]
;
; AL = [com_modem]
; AH = [com_line]
;
                or al,00001000B
                and ah,00011100B
                mov bx,[com_rec]
                cmp bx,[com_recint]
                jz get_status3
                or ah,00000001B
get_status3:    test [com_status],00000010B
                jz get_status4
                and [com_status],11111101B
                or ah,00000010B
get_status4:    mov bx,[com_tra]
                mov cx,bx
                cmp bx,[com_traend]
                jnz get_status5
                mov bx,[com_trastart]
                dec bx
get_status5:    inc bx
                cmp bx,[com_traint]
                jz get_status6
                or ah,00100000B
get_status6:    cmp cx,[com_traint]
                jnz get_status7
                sti
                add dx,5                ;Base+5
                mov cl,al
                in al,dx                ;Line Status Register
                sub dx,5                ;Base+0
                and al,01100000B
                xor al,01100000B
                mov al,cl
                jnz get_status7
                or ah,01000000B
get_status7:    sti
                ret

                ALIGN 4

;
; clearcom
;
; In:   DX = Base address
; Out:  CLI has been done
;
; Always safe to call, even if com port not open, does not restore interrupt
; pointers, only clearing the UART.
;
; If FOSSIL is opened, the PIC values will be restored.
;
; Note, may be called during unload with DS set to TSR.
;
clearcom:       add dx,3                ;dx=Base+3, Line Control Register
                cli
;
; 16750/16650
;
                test [com_config],00000110B     ;16750/16650?
                jz clearcom1
                mov al,[com_accenh]             ;Access Enhanced Feature Register
                out dx,al
                jmp $+2
                dec dx                  ;dx=Base+2, FIFO control register
                xor al,al               ;Clear Enhanced Feature Register
                out dx,al
                jmp $+2
                inc dx                  ;dx=Base+3
;
clearcom1:      mov al,[com_linectrl]   ;DLAB=0
                out dx,al
                jmp $+2
                dec dx                  ;dx=Base+2
                xor al,al               ;Disables FIFO
                out dx,al
                jmp $+2
                dec dx                  ;dx=Base+1
                xor al,al               ;Disable interrupts
                out dx,al
                jmp $+2
                jmp $+2
                out dx,al
                add dx,3                ;dx=Base+4, modem control register
                in al,dx
                jmp $+2
                and al,11110111B        ;Clear OUT2
                out dx,al
                sub dx,4                ;dx=Base+0
                mov [com_status],0      ;RTS clear
                ret

                ALIGN 4

;
; comsetup
;
; In:  DL = FOSSIL port number, with bit 7 = 0
; Out: CF = 1 --> Port number was 255, return success
;      CF = 0 --> DX = Base address
;
; If invalid port or port not opened then it does not return instead it
; calls the original INT 14H.
;
; Only use DL for port number due to bugs in other programs.
;
comsetup:       cmp dl,255
                jz comsetup1
                test dl,80H
                jnz comsetup2
                cmp dl,[fossil_port]
                jnz comsetup2
                mov dx,[com_base]
                clc
                ret

                ALIGN 4

comsetup1:      stc
                ret

                ALIGN 4

comsetup2:      add sp,2        ;Remove return address
                jmp jump_to_old

                ALIGN 4
;
; set_baud
;
; In:   DX = Base address
; Out:  CLI has been done
;
set_baud:       mov bx,[com_baud]
                add dx,3                ;dx=Base+3, Line Control Register
                mov al,[com_linectrl]   ;DLAB=0
                or al,10000000B         ;DLAB=1
                cli
                out dx,al
                jmp $+2
                sub dx,3                ;dx=Base+0, Divisor Latch LSB
                mov al,bl
                out dx,al
                jmp $+2
                inc dx                  ;dx=Base+1, Divisor Latch MSB
                mov al,bh
                out dx,al
                jmp $+2
                inc dx
                inc dx                  ;dx=Base+3, Line Control Register
                mov al,[com_linectrl]   ;DLAB=0
                out dx,al
                sub dx,3
                ret

                ALIGN 4

;
; read_55ms
;
; In:  ----
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

                ALIGN 4

;
; AH = 00h    Set baud rate
;
;         Parameters:
;             Entry:  AL = Baud rate code
;                     DX = Port number
;             Exit:   AX = Port status (see function 03h)
;
; This works the same as the  equivalent IBM PC BIOS call,  except that it
; ONLY selects a baud rate.  This is passed in the high order 3 bits of AL
; as follows:
;
;             010 =   300 baud
;             011 =   600  ''
;             100 =  1200  ''
;             101 =  2400  ''
;             110 =  4800  ''
;             111 =  9600  ''
;             000 = 19200  '' (Replaces old 110 baud mask)
;             001 = 38400  '' (Replaces old 150 baud mask)
;
; The low order 5 bits can be implemented or not by the FOSSIL, but in all
; cases, if the low order bits of AL are 00011,  the result should be that
; the communications device should be set to eight data bits, one stop bit
; and no parity. This setting is a  MINIMUM REQUIREMENT  of Fido, Opus and
; SEAdog.  For purposes of completeness,  here are the IBM PC "compatible"
; bit settings:
;
; Bits 4-3 define parity:     0 0       no parity
;                             1 0       no parity
;                             0 1      odd parity
;                             1 1     even parity
;
; Bit 2 defines stop bits:      0        1 stop bit;
;                               1      1.5 bits for 5-bit char;
;                                        2 for others
;
; Bits 1-0 character length:  0 0        5 bits
;                             0 1        6 bits
;                             1 0        7 bits
;                             1 1        8 bits
;
; X00: If port not open then
;        if usebios then jump to old
;        else if AH>=4 or DL>9 then C=1
;        else C=0 and do job
;
func00:         call comsetup
                jc func00a
                mov [info_baud],al
                call set_baud
                sti
                clc
func00a:        jmp func03a

                ALIGN 4

;
; AH = 01h    Transmit character with wait
;
;         Parameters:
;             Entry:  AL = Character
;                     DX = Port number
;             Exit:   AX = Port status (see function 03h)
;
; AL contains the character to be sent.   If there is room in the transmit
; buffer the return will be immediate,  otherwise it will wait until there
; is room to store the character in the transmit buffer.  On return, AX is
; set as in a status request (see function 03h).
;
; X00: If port not open then
;        if usebios then jump to old
;        else if AH>=4 or DL>9 then C=1
;        else C=0 and do job
;
func01:         call    comsetup
                jc      func01c
                mov     di,ax
                call    cputcomsub1
                jnc     func01b
                call    read_55ms
                mov     dx,[com_base]
                mov     si,ax
func01a:        call    cputcomsub1
                jnc     func01b
                call    read_55ms
                mov     dx,[com_base]
                sub     ax,si
                cmp     ax,546
                jb      func01a
                mov     ax,8000h
                jmp     ret_ax

func01b:        mov     ax,di
                mov     [bx],al
                mov     [com_tra],cx
                sti
                clc
func01c:        jmp  short func03a

                ALIGN 4

;
; AH = 02h    Receive character with wait
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   AH = 00h
;                     AL = Input character
;
; If there is a character  available in the  receive buffer,  returns with
; the next character in AL.  It will wait until a character is received if
; none is available.
;
; X00: If port not open then
;        if usebios then jump to old
;        else if AH>=4 or DL>9 then C=1
;        else C=0 and do job
;
; X00 retuns status in AH.
;
func02:         call    comsetup
                jc      func02c
                call    uart_poll
                mov     bx,[com_rec]
                cmp     bx,[com_recint]
                jne     func02b
                sti
                call    read_55ms
                mov     dx,[com_base]
                mov     si,ax
func02a:        call    uart_poll
                mov     bx,[com_rec]
                cmp     bx,[com_recint]
                jne     func02b
                sti
                call    read_55ms
                mov     dx,[com_base]
                sub     ax,si
                cmp     ax,546
                jb      func02a
                mov     ax,8000H
                jmp     ret_ax

func02b:        mov     al,[bx]
                call    cgetcomsub2
                xor     ah,ah
                jmp     ret_ax

func02c:        xor     ax,ax
                jmp     ret_ax

                ALIGN 4

;
; AH = 03h    Request status
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   AX = Status bit mask (see below)
;
; Returns with the line and modem status in AX.  Status bits returned are:
;
;         In AH:
;             Bit 0 = RDA  - input data is available in buffer
;             Bit 1 = OVRN - the input buffer has been overrun.  All
;                            characters received after the buffer is
;                            full should be discarded.
;             Bit 5 = THRE - room is available in output buffer
;             Bit 6 = TSRE - output buffer is empty
;
;         In AL:
;             Bit 3 = Always 1 (always return with this bit set to 1)
;             Bit 7 = DCD  - carrier detect
;
; This can be used by the application to determine  whether carrier detect
; (CD) is set,  signifying the presence/absence of a remote connection, as
; well as monitoring both the input and output buffer status.  Bit 3 of AL
; is always returned set to enable programs to use it as a carrier detect
; bit on hardwired (null modem) links.
;
; X00: If port not open then
;        if usebios then jump to old
;        else if AH>=4 or DL>9 then C=1
;        else C=0 and do job
;
func03:         call    comsetup
func03a:        jc      func03b
                call    get_status
                jmp     ret_ax

func03b:        mov     ax,8
                jmp     ret_ax

                ALIGN 4

;
; AH = 04h    Initialize driver
;
;         Parameters:
;             Entry:  DX = port number
;                   ( BX = 4F50h
;                     ES:CX = ^C flag address --- optional )
;             Exit:   AX = 1954h if successful
;                     BL = maximum function number supported
;                          (not counting functions 7Eh and above)
;                     BH = rev of FOSSIL doc supported
;
; This is used to tell the driver to begin  operations,  and to check that
; the driver is installed. This function should be called before any other
; communications calls are made.  At this point all interrupts involved in
; supporting the comm port (specified in DX) should be set up for handling
; by  the  FOSSIL, then  enabled.  If BX contains 4F50h,  then the address
; specified in ES:CX is that of a ^C flag byte in the application program,
; to be incremented when  ^C is detected in the keyboard service routines.
; This is an optional service and only need be supported on machines where
; the keyboard service can't (or won't) perform an INT 1Bh or INT 23h when
; a Control-C is entered.  DTR is raised by this call.  The baud rate must
; NOT be changed by this call.
;
; NOTE: Should an additional call to this service occur  (2 Inits or Init,
; Read,Init, etc.) the driver should reset all buffers, flow control, etc.
; to the INIT state and return SUCCESS.
;
;
; X00 sets Carry flag to 1
;
func1C:
func04:         call comsetup
                jnc func04b

func04a:        mov ax,1954H
                mov bx,INT14_REV*256+INT14_MAXFUNC
                jmp ret_ax_bx

func04b:        call clearcom

;
; Due to behavior in Windows 95 when ADF is loaded in AUTOEXEC.BAT,
; the PIC bits should be disabled.
;

                mov bx,[com_picmsk2]
                and bx,bx
                jz func04c
                in al,0A1H
                jmp $+2
                or al,bl
                out 0A1H,al
                jmp SHORT func04d

func04c:        mov bx,[com_picmsk1]
                in al,021H
                jmp $+2
                or al,bl
                out 021H,al

func04d:

;
; 16650/16750
;
                test [com_config],00000110B     ;16750/16650?
                jz func04e
                add dx,3                ;dx=Base+3, Line Control Register
                mov al,[com_accenh]     ;Access Enhanced Feature Register
                out dx,al
                jmp $+2
                dec dx                  ;dx=Base+2, FIFO control register
                mov al,[com_enhreg]     ;Enable Enhanced Feature Register
                out dx,al
                jmp $+2
                sub dx,2                ;dx=Base+0
;
func04e:        call set_baud
                add dx,2                ;dx=Base+2

                test [com_config],00000100B     ;16750?
                jnz func04f

                mov al,[com_fifoctrl]
                or al,00000111B         ;RCVR trigger level, Reset FIFO
                out dx,al

func04f:        add dx,2                ;dx=Base+4
                mov al,[com_modemctrl]
                out dx,al
                jmp $+2
                sub dx,3                ;dx=Base+1
                mov al,00001111B        ;Enable interrupts
                out dx,al
                jmp $+2
                jmp $+2
                out dx,al
                jmp $+2
                inc dx                  ;dx=Base+2
                in al,dx                ;Interrupt Identification Register
                jmp $+2
                add dx,3                ;dx=Base+5
                in al,dx                ;Line Status Register
                jmp $+2
                mov [com_line],al
                inc dx                  ;dx=Base+6
                in al,dx                ;Modem Status Register
                jmp $+2
                IFE POLL_MOD_STAT
                mov [com_modem],al
                ENDIF
                sub dx,6                ;dx=Base+0
                in al,dx                ;Receiver Data Register
                jmp $+2

                mov bx,[com_picmsk1]
                in al,21H
                jmp $+2
                and al,bh
                out 21H,al

                mov bx,[com_picmsk2]
                and bx,bx
                jz func04g
                in al,0A1H
                jmp $+2
                and al,bh
                out 0A1H,al
func04g:

                mov ax,[com_recstart]
                mov [com_rec],ax
                mov [com_recint],ax
                mov ax,[com_trastart]
                mov [com_tra],ax
                mov [com_traint],ax

                sti
                jmp func04a

                ALIGN 4

;
; AH = 05h    Deinitialize driver
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   None
;
; This is used to tell the driver that comm port operations are ended. The
; function should be called  when no more comm port functions will be used
; on the port specified in DX.  DTR is NOT affected by this call.
;
; X00 sets Carry flag to 1
;
func1D:
func05:         call comsetup
                jmp ret_none

                ALIGN 4

;
; AH = 06h    Raise/lower DTR
;
;         Parameters:
;             Entry:  DX = Port number
;                     AL = DTR state to be set (01h = Raise, 00h = Lower)
;             Exit:   None
;
; This function is used to control the DTR line to the modem. AL = 00h means
; lower DTR (disable the modem), and AL = 01h means to raise DTR (enable the
; modem).  No other function (except Init) should alter DTR.
;
func06:         call    comsetup
                jc      func06a
                and     al,1
                mov     cl,al
                add     dx,4
                cli
                in      al,dx
                jmp     short $+2
                and     al,0FEH
                or      al,cl
                out     dx,al
                sti
func06a:        jmp     ret_none


                ALIGN 4

;
; AH = 07h    Return timer tick parameters
;
;         Parameters:
;             Entry:  None
;             Exit:   AL = Timer tick interrupt number
;                     AH = Ticks per second on interrupt number in AL
;                     DX = Approximate number of milliseconds per tick
;
; This is used to  determine the parameters of the timer tick on any given
; machine.  Three numbers are returned:
;
;     AL =   Timer tick interrupt number
;     AH =   Ticks per second on interrupt number shown in AL
;     DX =   Milliseconds per tick (approximate)
;
; Applications can use this for critical timing  (granularity of less than
; one second) or to set up code  (such as a watchdog)  that is executed on
; every timer tick. See function 16h (add/delete function from timer tick)
; for the preferred way of actually installing such code.
;
func07:         mov     ax,18*256+TIMER_INT     ;X00 returns 18*256+08H
                mov     dx,55
                jmp     ret_ax_dx

                ALIGN 4

;
; AH = 08h    Flush output buffer
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   None
;
; This is used to force any pending output.   It does not return until all
; pending output has been sent.  You should use this call with care.  Flow
; control  (documented below)  can make your system hang on this call in a
; tight uninterruptible loop under the right circumstances.
;
func08:         call    comsetup
                jc      func08b
                add     dx,5
func08a:        nop
                nop
                cli
                mov     ax,[com_tra]
                cmp     ax,[com_traint]
                sti
                jnz     func08a
                in      al,dx
                and     al,60H
                xor     al,60H
                jnz     func08a
func08b:        jmp     ret_none

                ALIGN 4

;
; AH = 09h    Purge output buffer
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   None
;
; This is used to purge any pending output.   Any output data remaining in
; the output buffer (not transmitted yet) is discarded.
;
func09:         call    comsetup
                jc      func09a
                inc dx
                inc dx                  ;dx=Base+2
                cli
                mov     ax,[com_tra]
                mov     [com_traint],ax
                mov al,[com_fifoctrl]
                or al,00000101B         ;RCVR trigger level, Reset FIFO
                out dx,al
                sti
func09a:        jmp     ret_none

                ALIGN 4

;
; AH = 0Ah    Purge input buffer
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   None
;
; This is used to purge any pending input.   Any input data which is still
; in the buffer is discarded.
;
func0A:         call comsetup
                jc func0Ab
                inc dx
                inc dx                  ;dx=Base+2
                cli
                mov ax,[com_recint]
                mov [com_rec],ax
                mov al,[com_fifoctrl]
                or al,00000011B                 ;RCVR trigger level, Reset FIFO
                out dx,al
                test [com_status],00010000B     ;RTS
                jz func0Aa
                dec dx
                dec dx                  ;dx=Base+0
                call rts_release3
func0Aa:        sti

func0Ab:        jmp ret_none

                ALIGN 4

;
; AH = 0Bh    Transmit no wait
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   AX = 0001h - Character was accepted
;                        = 0000h - Character was not accepted
;
; This is exactly the same as the "regular"  transmit call, except that if
; the driver is  unable to  buffer the character  (the buffer is full),  a
; value of 0000h is returned in AX. If the driver accepts the character
; (room is available),  0001h is returned in AX.
;
func0B:         call    comsetup
                jc      func0Ba
                call    cputcomsub1
                jc      func0Bb
                mov     [bx],al
                mov     [com_tra],cx
                call    uart_poll
                sti
func0Ba:        mov     ax,1
                jmp     ret_ax

func0Bb:        xor     ax,ax
                jmp     ret_ax

                ALIGN 4

;
; AH = 0Ch    Non-destructive read-ahead
;
;         Parameters:
;             Entry:  DX = Port number
;             Exit:   AH = 00h           - Character is
;                     AL = Next character    available
;                     AX = FFFFh         - Character is not available
;
; Return in AL the next character in the receive buffer.  If the receive
; buffer is empty,  return  FFFFh.  The  character  returned  remains in
; the receive buffer. Some applications call this "peek".
;
func0C:         call    comsetup
                jc      func0Cb
                call    uart_poll
                mov     bx,[com_rec]
                cmp     bx,[com_recint]
                je      func0Ca
                mov     al,[bx]
                sti
                xor     ah,ah
                jmp     ret_ax

func0Ca:        sti
                mov     ax,0FFFFH
                jmp     ret_ax

func0Cb:        xor     ax,ax
                jmp     ret_ax

                ALIGN 4

;
; AH = 0Dh    Keyboard read without wait
;
;         Parameters:
;             Entry:  None
;             Exit:   AX = IBM-style scan code (Character available)
;                        = FFFFh               (Character not available)
;
; Return in  AX the  next character  (non-destructive read ahead)  from the
; keyboard; if nothing is currently in the keyboard buffer, return FFFFh in
; AX.   Use IBM-style  function  key mapping  in the high order byte.  Scan
; codes for non-"function" keys  are not specifically required,  but may be
; included. Function keys return 00h in AL and the "scan code" in AH.
;
;
; X00 sets the Z flag
;
func0D:         mov     ah,1
                int     16h
                jnz     func0Da
                mov     ax,0FFFFH
func0Da:        jmp     ret_ax

                ALIGN 4

;
; AH = 0Eh    Keyboard read with wait
;
;         Parameters:
;             Entry:  None
;             Exit:   AX = IBM-style scan code
;
; Return in AX the next character from the keyboard;  wait if no character
; is available. Keyboard mapping should be the same as function 0Dh.
;
func0E:         xor     ah,ah
                int     16h
                jmp     ret_ax

                ALIGN 4

;
; AH = 0Fh    Enable or disable flow control
;
;         Parameters:
;             Entry:  AL = Bit mask describing requested flow control
;                     DX = Port number
;             Exit:   None
;
; TRANSMIT flow control allows the "other end" to restrain the transmitter
; when you are  over-running it.  RECEIVE flow control tells the FOSSIL to
; attempt to do just that if it is being overwhelmed.
;
; Two kinds of basic flow control are supported:
;
;             Bit 0 = 1       Xon/Xoff on transmit
;             Bit 1 = 1       CTS/RTS (CTS on transmit, RTS on receive)
;             Bit 2           Reserved
;             Bit 3 = 1       Xon/Xoff on Receive
;
; Flow control is enabled, or disabled, by setting the appropriate bits in
; AL  for the types of flow control we want to ENABLE (value = 1),  and/or
; DISABLE  (value = 0),  and calling this function.  Bit 2 is reserved for
; DSR/DTR,  but is not currently supported in any implementation.
;
; Enabling  transmit  Xon/Xoff will cause the FOSSIL  to stop transmitting
; upon receiving an Xoff.  The FOSSIL will resume transmitting when an Xon
; is received.
;
; Enabling CTS/RTS will cause the FOSSIL to cease transmitting when CTS is
; lowered.  Transmission will resume  when CTS is raised.  The FOSSIL will
; drop RTS when the receive buffer reaches a predetermined percentage full
; The FOSSIL will  raise RTS  when the  receive buffer  empties below  the
; predetermined  percentage full.  The  point(s)  at which  this occurs is
; left to the individual FOSSIL implementor.
;
; Enabling receive  Xon/Xoff will cause the FOSSIL to send a Xoff when the
; receive buffer reaches a pre-determined percentage full.  An Xon will be
; sent when the receive buffer empties below the pre-determined percentage
; full. The point(s) at which this occurs is left to the individual FOSSIL
; implementor.
;
; Applications  using this  function  should set all bits  ON  in the high
; nibble of AL as well.  There is a compatible  (but not identical) FOSSIL
; driver implementation that uses the  high nibble as a control mask.   If
; your application sets the high nibble to all ones,  it will always work,
; regardless of the method used by any given driver.
;
func0F:         call comsetup
                jc func0Fb
                add dx,4        ;Base+4, modem control register
                cli
                in al,dx
                or al,00000010B        ;RTS
                test [com_status],00010000B        ;RTS
                jz func0Fa
                and al,11111101B        ;RTS off
func0Fa:        out dx,al
                sti
func0Fb:        jmp ret_none

                ALIGN 4

;
; AH = 10h    Extended Control-C / Control-K checking and transmit on/off
;
;         Parameters:
;             Entry:  AL = Bit mask (see below)
;                     DX = Port number
;             Exit:   AX = 0001h - Control-C/K has been received
;                        = 0000h - Control-C/K has not been received
;
; This is used for BBS  operation,  primarily.  A bit mask is passed in AL
; with the following flags:
;
;             Bit 0   Enable/disable Control-C / Control-K checking
;             Bit 1   Disable/enable the transmitter
;
; The Enable (bit 0 = 1) and Disable (Bit 0 = 0) Control-C/Control-K check
; function is meant primarily for BBS use. When the checking is enabled, a
; Control-C or Control-K received  from the communications port will set a
; flag internal to the FOSSIL driver,  but will not be stored in the input
; buffer. The next use of this function will return the value of this flag
; in register AX then clear the flag for the next occurrence. The returned
; value is used by the BBS  software to determine whether output should be
; halted or not.
;
; The Disable (Bit 1 = 1) and Enable (Bit 1 = 0) Transmitter function lets
; the application restrain the asynchronous driver from output in much the
; same way as XON/XOFF would.
;
func10:         call comsetup
                jc func10d
                test al,00000010B               ;Disable the transmitter
                jz func10a
;
; Disable the transmitter
;
                or [com_status],10000000B       ;Transmitter disabled
                jmp SHORT func10b

;
; Enable the transmitter
;
func10a:        test [com_status],10000000B     ;Transmitter disabled
                jz func10b
                and [com_status],01111111B      ;Transmitter enabled
                push ax
                call uart_poll
                sti
                pop ax

func10b:        test al,00000001B               ;Enable Control-C / Control-K checking
                jz func10c

;
; Enable Control-C / Control-K checking
;
                cli
                or [com_status],00000100B       ;Enable Ctrl-C and Ctrl-K check
                mov al,[com_status]
                and [com_status],11111110B      ;Clear Ctrl-C or Ctrl-K recevied
                sti
                and al,00000001B                ;Ctrl-C or Ctrl-K recevied
                xor ah,ah
                jmp ret_ax

;
; Disable Control-C / Control-K checking
;
func10c:        and [com_status],11111010B      ;Disable Ctrl-C and Ctrl-K check
func10d:        xor ax,ax
                jmp ret_ax

                ALIGN 4

;
; AH = 11h    Set current cursor location.
;
;         Parameters:
;             Entry:  DH = Row (line)
;                     DL = Column
;             Exit:   None
;
; This function looks exactly like like INT 10h, subfunction 2, on the IBM
; PC. The cursor location is passed in DX: row in DH and column in DL. The
; function treats the screen as a coordinate  system whose origin (0,0) is
; the upper left hand corner of the screen.
;
func11:         mov ah,2
                xor bh,bh
                int 10H
                jmp ret_none

                ALIGN 4

;
; AH = 12h    Read current cursor location.
;
;         Parameters:
;             Entry:  None
;             Exit:   DH = Row (line)
;                     DL = Column
;
; Looks exactly like INT 10h,  subfunction 3,  on the IBM PC.  The current
; cursor location  (using the same coordinate  system as  function 16h) is
; passed back in DX.
;
func12:         mov ah,3
                xor bh,bh
                int 10H
                jmp ret_dx

                ALIGN 4

;
; AH = 13h    Single character ANSI write to screen.
;
;         Parameters:
;             Entry:  AL = Character to display
;             Exit:   None
;
; The character in AL is sent to the screen by the fastest method possible
; that allows ANSI processing to occur (if available). This routine should
; not be used in such a way that DOS output  (which is not re-entrant) can
; not be employed by some FOSSIL driver to perform the function  (in fact,
; on the IBM PC that is likely to be how it's done).  On some systems such
; as the DEC Rainbow this will be a very fast method of screen writing.
;
func13:         mov     ah,2
                mov     dl,al
                int     21H
                jmp     ret_none

                ALIGN 4

;
; AH = 14h    Enable or disable watchdog processing
;
;         Parameters:
;             Entry:  AL = 01h - Enable watchdog
;                        = 00h - Disable watchdog
;                     DX = Port number
;             Exit:   None
;
; When watchdog is enabled,   the state of the carrier detect (CD) line on
; the comm port specified in DX should be constantly monitored. Should the
; state of that line become FALSE (carrier lost), the system should be re-
; booted, to enable the BBS (or other application) to start up again. This
; monitor is not affected by Init/Uninit etc.
;
func14:         call comsetup
                jc func14b

func14a:        mov bx,[timer_watchini]
                cli
                mov [timer_watchcnt],bx
                and [com_config],11111110B
                and al,1
                or [com_config],al
                sti
func14b:        jmp ret_none

                ALIGN 4

;
; AH = 15h    Write character to screen using BIOS support routines
;
;         Parameters:
;             Entry:  AL = Character to display
;             Exit:   None
;
; The character in AL is sent to the screen using  BIOS-level Input/Output
; routines. This differs from function 13h in that DOS I/O CAN NOT be used,
; as this function might be called from driver level.
;
func15:         mov ah,0EH
                mov bx,7
                int 10H
                jmp ret_none

                ALIGN 4

;
; AH = 16h    Insert or delete a function from the timer tick chain
;
;         Parameter:
;             Entry:  AL = 01h - Add a function
;                        = 00h - Delete a function
;                     ES = Segment of function
;                     DX = Offset of function
;             Exit:   AX = 0000h - Operation successful
;                        = FFFFh - Operation unsuccessful
;
; This function is used to allow a  central authority  to manage the timer
; interrupts, so that as code is loaded and unloaded, the integrity of the
; "chain" is not compromised.  Rather than using the traditional method of
; saving the old contents of the timer vector, storing the address of your
; routine there,  and executing a far call to the "old" routine when yours
; is done, instead you call this function. It manages a list of such entry
; points and calls them on a timer tick (interrupt) using a FAR call.  All
; the usual cautions about making DOS calls apply (that is, DON'T!).
;
; This makes it possible for a program to get in and out of the tick chain
; without having to know whether another program has also done so since it
; first insinuated itself.   At least 4 entries should be available in the
; driver's table (including one to be used by Watchdog if implemented that
; way).
;
;
; X00 returns number of ticks per second on operation successful.
;
func16:         mov     si,OFFSET timer_calls
                mov     cx,NUM_TIMERS
                mov     bx,es
                and     al,1
                cli
                jz      func16c

                IF USE_TIMER

func16a:        mov     ax,[si]
                or      ax,[si+2]
                jz      func16b
                add     si,4
                loop    func16a

                ENDIF

                mov     ax,0FFFFH
                jmp     func16e

func16b:        mov     [si],dx
                mov     [si+2],bx
                mov     ax,18
                jmp     func16e

func16c:        cmp     dx,[si]
                jne     func16d
                cmp     bx,[si+2]
                jne     func16d
                xor     ax,ax
                mov     [si],ax
                mov     [si+2],ax
                jmp     func16e

func16d:        add     si,4
                loop    func16c

                mov     ax,0FFFFH
func16e:        sti
                jmp     ret_ax

                ALIGN 4

;
; AH = 17h    Reboot system
;
;         Parameters:
;             Entry:  AL = 00h - "Cold boot"
;                        = 01h - "Warm boot"
;
; Perform the old 3-finger salute.  Used in extreme emergency by code that
; can't seem to find a "clean" way out of the trouble it has gotten itself
; into.  Hopefully it won't happen while you're computing something in the
; other half of a DoubleDOS system. If your machine can make a distinction
; between a "cold" (power-up, self-test and boot) and a "warm" (just boot)
; bootstrap,  your FOSSIL should support the flag in AL. Otherwise just do
; whatever bootstrap is possible.
;
func17:         mov dx,1234H
                and al,1
                jnz reboot1

reboot:         xor dx,dx
reboot1:        xor ax,ax
                mov ds,ax
                mov ds:[0472H],dx
                pushf
                push ax
                popf
                pushf
                pop ax
                and ah,0F0H
                xor ah,0F0H
                jnz reboot3
;
; Computer type PC
;
reboot2:        popf
                cli
                mov ax,2
                push ax
                xor ax,ax
                popf
                mov ss,ax
                mov sp,0FFFEH
                mov ds,ax
                mov es,ax
                jmp start_pc
;
; Computer type AT
;
reboot3:        popf
                and dx,dx
                jnz reboot6
;
; Computer type AT cold boot
;
                cli
                mov al,8FH              ;Disable NMI
                out 70H,al
                jmp SHORT $+2
                xor al,al               ;0 -> Shutdown statys byte
                out 71H,al
                xor cx,cx
reboot4:        in al,64H
                jmp SHORT $+2
                test al,00000010B       ;Loop while input buffer full
                loopnz reboot4
                jmp SHORT $+2
                IF 0
                mov al,0FEH             ;Pulse RESET
                out 64H,al
                ELSE
                in al,60H               ;Dummy read
                jmp SHORT $+2
                jmp SHORT $+2
                mov al,0D0H             ;Read output port
                out 64H,al
                xor cx,cx
reboot5:        in al,64H
                jmp SHORT $+2
                test al,00000001B       ;Loop while output buffer empty
                loopz reboot5
                in al,60H
                jmp SHORT $+2
                and al,11111110B        ;Clear bit 0 for RESET
                mov ah,al
                mov al,0D1H             ;Write output port
                out 64H,al
                jmp SHORT $+2
                jmp SHORT $+2
                mov al,ah
                out 60H,al
                ENDIF
                jmp SHORT $+2
                jmp SHORT $+2
                in al,60H               ;Dummy read
;
; Computer type AT warm boot
;
reboot6:        mov ax,2
                push ax
                xor ax,ax
                popf
                mov ss,ax
                mov sp,0FFFEH
                mov ds,ax
                mov es,ax
                jmp start_at

                ALIGN 4

;
; AH = 18h    Read block (transfer from FOSSIL to user buffer)
;
;         Parameters:
;             Entry:  CX = Maximum number of characters to transfer
;                     DX = Port number
;                     ES = Segment of user buffer
;                     DI = Offset into ES of user buffer
;             Exit:   AX = Number of characters actually transferred
;
; A "no-wait"  block read of 0 to FFFFh characters from the FOSSIL inbound
; ring buffer to the calling routine's buffer. ES:DI are left unchanged by
; the call; the count of bytes actually transferred will be returned in AX.
;
                IF 1            ;Different implementation

func18:         call comsetup
                jc func18h
                jcxz func18h
                cli
                mov ax,[com_recint]
                mov si,[com_rec]
                sub ax,si
                jz func18g              ;No bytes
                ja func18b
func18a:        add ax,[com_reclen]     ;AX=Number of bytes in buffer to read
func18b:        cmp ax,cx
                jb func18c
                mov ax,cx
func18c:        push ax                 ;Bytes to move
                mov cx,[com_reclim]
                sub cx,si               ;Bytes left to wrap
                cmp cx,ax
                ja func18d
                sub ax,cx
                rep movsb
                mov si,[com_recstart]
func18d:        mov cx,ax
                rep movsb
                mov [com_rec],si
                test [com_status],00010000B        ;RTS
                jnz func18f
                sti
func18e:        pop ax
                jmp ret_ax

func18f:        mov bx,si
                call rts_release1
                jmp func18e

                ALIGN 4

func18g:        push cx
                call uart_poll
                pop cx
                mov ax,[com_recint]
                mov si,[com_rec]
                sub ax,si
                ja func18b
                jnz func18a
func18h:        xor ax,ax
                jmp ret_ax

                ELSE            ;Different implementation

func18:         mov si,di
                call comsetup
                jc func18a
                jcxz func18a
                push cx
                call uart_poll
                pop cx
                mov bx,[com_rec]
                cmp bx,[com_recint]
                jnz func18b
                sti
func18a:        mov ax,di
                sub ax,si
                jmp ret_ax

                ALIGN 4

func18b:        mov al,[bx]
                cmp bx,[com_recend]
                jz func18d
                inc bx
func18c:        stosb
                cmp bx,[com_recint]
                loopnz func18b

                call cgetcomsub3
                jmp SHORT func18a

func18d:        mov bx,[com_recstart]
                jmp SHORT func18c

                ENDIF           ;Different implementation

                ALIGN 4

;
; AH = 19h    Write block (transfer from user buffer to FOSSIL)
;
;         Parameters:
;             Entry:  CX = Maximum number of characters to transfer
;                     DX = Port number
;                     ES = Segment of user buffer
;                     DI = Offset into ES of user buffer
;             Exit:   AX = Number of characters actually transferred
;
;
; A  "no-wait"  block  move of 0  to FFFFh  characters  from  the  calling
; program's  buffer into  the  FOSSIL outbound ring buffer. ES:DI are left
; unchanged by the call;  the count of bytes actually transferred  will be
; returned in AX.
;
                IF 1            ;Different implementation

func19:         mov si,di
                call comsetup
                jc func19x
                jcxz func19x
;
; No CLI needed. Interrupt routine will only change com_traint.
;
                mov ax,[com_traint]
                mov di,[com_tra]
                sub ax,di
                ja func19a
                add ax,[com_tralen]
func19a:        dec ax                  ;AX=Number of free bytes in buffer
                cmp ax,cx
                jb func19b
                mov ax,cx
func19b:        push ax                 ;Bytes to move
                mov cx,[com_tralim]
                mov bx,[com_trastart]
                push ds
                push es
                push ds
                push es
                pop ds
                pop es
                sub cx,di               ;Bytes left to wrap
                cmp cx,ax
                ja func19c
                sub ax,cx
                rep movsb
                mov di,bx
func19c:        mov cx,ax
                rep movsb
                pop es
                pop ds
                mov [com_tra],di
                call uart_poll
                sti
                pop ax
                jmp ret_ax

func19x:        xor ax,ax
                jmp ret_ax

                ELSE            ;Different implementation

func19:         mov si,di
                call comsetup
                jc func19c
                jcxz func19c
                push di
                mov di,cx

                ALIGN 4

func19a:        call cputcomsub1
;
; Out:  CF = 1 --> No space
;                  AX = 0
;       CF = 0 --> Space
;                  AX = 1
;                  DS:BX = Empty space in transmit buffer
;                  DS:CX = One character ahead
;                  CLI has been done
;
                jc func19b
                lods BYTE PTR es:[si]
                mov [bx],al
                mov [com_tra],cx
                call uart_poll
                sti
                dec di
                jnz func19a

func19b:        pop di
func19c:        mov ax,si
                sub ax,di
                jmp ret_ax

                ENDIF           ;Different implementation

                ALIGN 4

;
; AH = 1Ah    Break begin or end
;
;         Parameters:
;             Entry:  AL = 01h - Start sending 'break'
;                        = 00h - Stop sending 'break'
;                     DX = port number
;             Exit:   None
;
; Send a break signal to the modem. If AL=01h the driver will commence the
; transmission of a break.  If AL=00h the driver will end the break.  This
; is useful for communications with devices that can only go into 'command
; mode' when a BREAK is received. Note: the application is responsible for
; the timing of the BREAK.  Also,  if the FOSSIL has been restrained by an
; Xoff received from the modem, the flag will be cleared.   An Init or Un-
; Init will stop an in-progress BREAK.
;
func1A:         call comsetup
                jc func1Ae
                call do_break   ;Will also set baud
func1Ae:        jmp ret_none

                ALIGN 4

do_break:       and al,1
                jnz do_break1
                add dx,3                ;dx=Base+3, Line Control Register
                IF 1
                mov al,[com_linectrl]   ;DLAB=0
                out dx,al
                ELSE
                cli
                in al,dx
                jmp $+2
                and al,00111111B        ;Clear break and DLAB=0
                out dx,al
                sti
                ENDIF
                sub dx,3                ;dx=Base+0
                ret

                ALIGN 4

do_break1:      inc dx
                inc dx                  ;dx=Base+2, Interrupt Identification Register
                cli
                mov ax,[com_tra]
                mov [com_traint],ax
                mov al,[com_fifoctrl]
                or al,00000101B         ;RCVR trigger level, Reset FIFO
                out dx,al
                sti
                jmp $+2
                add dx,3                ;dx=Base+5, Line Status Register
do_break2:      in al,dx
                and al,00100000B        ;Transmitter Holding Register Empty
                jz do_break2
                sub dx,5                ;dx=Base+0, Transmitter Holding Register
                xor al,al
                out dx,al
                jmp $+2
                add dx,5                ;dx=Base+5, Line Status Register
do_break3:      in al,dx
                and al,00100000B        ;Transmitter Holding Register Empty
                jz do_break3
                dec dx
                dec dx                  ;dx=Base+3, Line Control Register
                IF 1
                mov al,[com_linectrl]   ;DLAB=0
                or al,01000000B         ;Set break
                out dx,al
                ELSE
                cli
                in al,dx
                jmp $+2
                or al,01000000B         ;Set break
                out dx,al
                sti
                ENDIF
                inc dx
                inc dx                  ;dx=Base+5, Line Status Register
do_break4:      in al,dx
                and al,01000000B        ;Transmitter Empty
                jz do_break4
                sub dx,5                ;dx=Base+0
                ret

                ALIGN 4

;
; AH = 1Bh    Return information about the driver
;
;         Parameters:
;             Entry:  CX = Size of user info buffer in bytes
;                     DX = Port number
;                     ES = Segment of user info buffer
;                     DI = Offset into ES of user info buffer
;             Exit:   AX = Number of bytes actually transferred
;
; Transfer information about the driver and its current status to the user
; for use in determining,  at the application level, limits of the driver.
; Designed to assist  "generic" applications  to adjust to "foreign" gear.
;
; The data structure currently returned by the driver is as follows (sorry
; but you'll have to live with assembly syntax):
;
;     info    equ     $               ; define begin of structure
;     strsiz  dw      info_size       ; size of the structure in bytes
;     majver  db      curr_fossil     ; FOSSIL spec driver conforms to
;     minver  db      curr_rev        ; rev level of this specific driver
;     ident   dd      id_string       ; "FAR" pointer to ASCII ID string
;     ibufr   dw      ibsize          ; size of the input buffer (bytes)
;     ifree   dw      ?               ; number of bytes left in buffer
;     obufr   dw      obsize          ; size of the output buffer (bytes)
;     ofree   dw      ?               ; number of bytes left in the buffer
;     swidth  db      screen_width    ; width of screen on this adapter
;     sheight db      screen_height   ; height of screen    "     "
;     baud    db      ?               ; ACTUAL baud rate, computer to modem
;     info_size equ $-info
;
; The ident string should be  null-terminated,  and NOT contain a newline.
; The baud rate byte contains the bits that  Function 00h would use to set
; the port to that speed.
;
; The fields related to a particular port (buffer size,  space left in the
; buffer,  baud rate) will be undefined if port FFh  or an invalid port is
; contained in DX.
;
; Additional information will always be passed after these,  so that,  for
; example, offset "sheight" will never change with FOSSIL revision changes.
;
; The functions below are not necessarily FOSSIL related. However, because
; dispatchers  that support them are hooked on Interrupt 14H,  it behooves
; the FOSSIL developer to support them as well to avoid fragmenting memory
; with several dispatchers.
;
func1B:         call comsetup   ;Handle DL=FF as active port
;
; Video info
;
                push cx
                push di
                push es
                push bp
                mov ah,0FH
                int 10H
                mov cl,ah
                xor ah,ah
                mov [info_swidth],cl
                xor dl,dl
                xor bx,bx
                mov ax,1130H
                int 10H
                xor dh,dh
                and dl,dl
                jnz func1Ba
                mov dl,25
                jmp SHORT func1Bc

func1Ba:        xor ax,ax
                mov es,ax
                cmp dl,es:[0484H]       ;Video rows
                jz func1Bb
                dec dl
func1Bb:        inc dl
func1Bc:        mov [info_sheight],dl
                pop bp
                pop es
                pop di
                pop cx
;
; Buffer info
;
                cli
                mov ax,[com_traint]
                sub ax,[com_tra]
                ja func1Bd
                add ax,[com_tralen]
func1Bd:        dec ax
                mov [info_ofree],ax
                mov ax,[com_rec]
                sub ax,[com_recint]
                ja func1Be
                add ax,[com_reclen]
func1Be:        dec ax
                mov [info_ifree],ax
                sti
;
; Copy
;
                cmp cx,info_size
                jbe func1Bf
                mov cx,info_size
func1Bf:        mov ax,cx
                mov [info_strsiz],ax
                mov si,info_struct
                rep movsb
                jmp ret_ax

                ALIGN 4

;
; Function 1Eh - Extended line control initialization.
;
; This  function is intended to exactly emulate the PS/2's BIOS INT
; 14 services, function 4.  Some  or all of the functions  provided
; here are duplicated by other X00 functions.
;
;      Input:    AH = 1Eh
;
;                AL = Break, Where:
;                   = 00h, No break and/or turn off break
;                   = 01h, Start send of break.
;
;                BH = Parity, where:
;                   = 00h, No parity
;                   = 01h, Odd parity
;                   = 02h, Even parity
;                   = 03h, Mark parity (always 1)
;                   = 04h, Space parity (always 0)
;
;                BL = Stop bits, where:
;                   = 00h, One stop bit
;                   = 01h, Two stop  bits for 6,  7 and 8  bit word
;                          length, 1  and 1/2  stop bits for  5 bit
;                          word length.
;
;                CH = Word length, where:
;                   = 00h, 5 bits
;                   = 01h, 6 bits
;                   = 02h, 7 bits
;                   = 03h, 8 bits
;
;                CL = Baud rate, where:
;                   = 00h, 110 baud
;                   = 01h, 150 baud
;                   = 02h, 300 baud
;                   = 03h, 600 baud
;                   = 04h, 1200 baud
;                   = 05h, 2400 baud
;                   = 06h, 4800 baud
;                   = 07h, 9600 baud
;                   = 08h, 19200 baud
;                   The following are FOSSIL only baud rates:
;                   = 80h, 28800 baud
;                   = 81h, 38400 baud
;                   = 82h, 57600 baud
;                   = 83h, reserved (future 76800 baud)
;                   = 84h, 115200 baud
;                   = 0FFh, re-enable function 0 to set baud
;
;                DX = Port number
;
;      Output:   AX = Port status (see function 03h)
;
; If  locked at X00 load  time, the appropriate  parameters of this
; function are ignored.
;
func1E:         call comsetup
                jc func1Ea
                call do_break   ;Will also set baud
                sti
                clc
func1Ea:        jmp func03a

                ALIGN 4

;
; Function 1Fh - Extended serial port status/control.
;
; This  function is intended to exactly emulate the PS/2's BIOS INT
; 14 services, function  5.  Some or all of  the functions provided
; here are duplicated by other X00 functions.   This function has 2
; subfunctions specified by AL.
;
; Subfunction 00h - Read MCR
;
;      Input:    AH = 1Fh
;                AL = 00h, Read modem control register (MCR)
;                DX = Port number
;
;      Output:   AX = Port status (see function 03h)
;                BL = Modem control register, where:
;                     Bits 7-5 = 0 (Reserved)
;                     Bit 4    = 1 Loopback mode
;                     Bit 3    = 1 OUT2 (interrupts) enabled
;                     Bit 2    = 1 OUT1 active
;                     Bit 1    = 1 Request to send active
;                     Bit 0    = 1 Data terminal ready (DTR) active
;
; Subfunction 01h - Write MCR
;
;      Input:    AH = 1Fh
;                AL = 01h, Write modem control register (MCR)
;                BL = Modem control register, where:
;                     Bits 7-5 = 0 (Reserved)
;                     Bit 4    = 1 Set loopback mode
;                     Bit 3    = 1 Set OUT2 enable interrupts
;                     Bit 2    = 1 Set OUT1 active (on)
;                     Bit 1    = 1 Set Request to send active (on)
;                     Bit 0    = 1 Set DTR active (on)
;                DX = Port number
;
;      Output:   AX = Port status (see function 03h)
;
; In subfunction 01h (write  MCR) X00 will force bit 3  to 1.  That
; is,  X00  will not  allow  the  communications interrupts  to  be
; disabled.
;
; RTS may  be used  as a  flow  control signal  by X00.   When  the
; application program writes the MCR, the  RTS bit is treated as an
; RTS enable  bit.   This  means  that X00  will always  allow  the
; application program to turn RTS off.  However, X00 will  not turn
; on RTS unless it is safe to do so.
;
; Note, BH not changed!
;
; RTS is allowed to be set on, if buffers are full, it will be taken
; care off on the next character received.
;
func1F:         call comsetup
                jc func1Fd
                add dx,4        ;Base+4, modem control register
                cmp al,1
                cli
                in al,dx
                jz func1Fa
                mov bl,al
                jmp func1Fc

func1Fa:        IFE LOCK_MOD_CTRL
                mov al,bl
                ENDIF
                test [com_status],00010000B        ;RTS
                jz func1Fb              ;RTS not deactivated
                and al,11111101B        ;RTS off
func1Fb:        or al,00001000B         ;Interrupts enabled
                out dx,al

func1Fc:        sub dx,4                ;Base+0
                push bx
                call get_status         ;Will do STI
                pop bx
                jmp ret_ax_bx

func1Fd:        cmp al,1
                jz func1Fe
                mov bl,00001011B
func1Fe:        mov ax,8
                jmp ret_ax_bx

                ALIGN 4

;
; Function 20h - Read with no wait (destructive).
;
;
;      Input:    AH = 20h
;                DX = Port number
;
;      Output:   AH = 00h if character is available
;                AL = Next character if available
;                AX = 0FFFFh If no character is available
;
; This function returns the next character from the receive buffer.
; If the receive buffer is  empty, 0FFFFh is returned in AX.   This
; function  is the same as  function 0Ch except  that any character
; returned is removed from the receive buffer.
;
func20:         call comsetup
                jc func20b
                call uart_poll
                mov bx,[com_rec]
                cmp bx,[com_recint]
                je func20a
                mov al,[bx]
                call cgetcomsub2
                xor ah,ah
                jmp ret_ax

func20a:        sti
                mov ax,0FFFFH
                jmp ret_ax

func20b:        xor ax,ax
                jmp ret_ax

                ALIGN 4

;
; Function 21h - Stuff/Poke the receive buffer.
;
;
;      Input:    AH = 20h
;                AL = Character to place in the receive buffer
;
;      Output:   Nothing
;
; This function will  insert the passed character  into the receive
; buffer (at the end).  Subsequent reading of the serial input will
; read the character.  The character is inserted at the  end of the
; buffer (as though it were just received).
;
; The  character is inserted into the receive buffer by calling the
; receive interrupt  routine.    All  normal  receive  checking  is
; preformed on the character.  Some things to note are:
;
;      If  receiving  of  Xon/Xoff  is   enabled  and  an  Xoff  is
;      stuffed/poked  into the  buffer,  the transmitter  will stop
;      until a an Xon is received or stuffed/poked.
;
;      If  Control C/K  checking is  enabled and  a Control  C/K is
;      stuffed/poked, then the character  is not put in  the buffer
;      and the internal flags is set.
;
; The above should give you a little to think about when using this
; function.
;
; This  function  is intended  to be  fully  re-entrant.   Thus, it
; should be callable from timer tick processing etc.
;
;
; DX = Port
;
func21:         call comsetup
                jc func21a
                cli
                call receive_poke
                sti
func21a:        jmp ret_none

                ALIGN 4

func_table      DW OFFSET func00
                DW OFFSET func01
                DW OFFSET func02
                DW OFFSET func03
                DW OFFSET func04
                DW OFFSET func05
                DW OFFSET func06
                DW OFFSET func07
                DW OFFSET func08
                DW OFFSET func09
                DW OFFSET func0A
                DW OFFSET func0B
                DW OFFSET func0C
                DW OFFSET func0D
                DW OFFSET func0E
                DW OFFSET func0F
                DW OFFSET func10
                DW OFFSET func11
                DW OFFSET func12
                DW OFFSET func13
                DW OFFSET func14
                DW OFFSET func15
                DW OFFSET func16
                DW OFFSET func17
                DW OFFSET func18
                DW OFFSET func19
                DW OFFSET func1A
                DW OFFSET func1B
                DW OFFSET func1C
                DW OFFSET func1D
                DW OFFSET func1E
                DW OFFSET func1F
                DW OFFSET func20
                DW OFFSET func21

APP_NUM         EQU 40H ;80H to BFH

app_table       DD APP_NUM DUP(0)

oldint14        DD 0
                DB 14H,'INT'

fossil:         jmp SHORT fossil1

                DB 'ADF',0
                DW 1954H
                DB INT14_MAXFUNC
                DB 0

fossil1:        sti
                push ax
                push bx
                push cx
                push dx
                push si
                push di
                push ds
                mov si,cs
                mov ds,si
                cld
                cmp ah,INT14_MAXFUNC
                ja high_funcs
                mov si,ax
                mov al,ah
                xor ah,ah
                shl ax,1
                xchg si,ax
                jmp [func_table+si]

                ALIGN 4

jump_to_old1:   add sp,4

jump_to_old:    pop ds
                pop di
                pop si
                pop dx
                pop cx
                pop bx
                pop ax
                jmp cs:[oldint14]

                ALIGN 4

;
; AH = 7Eh    Install an "external application" function
;
;         Parameters:
;             Entry:  AL = Code assigned to external application
;                     DX = Offset of application entry point
;                     ES = Segment of application entry point
;             Exit:   AX = 1954h
;                     BL = Code assigned to application (same as input AL)
;                     BH = 01h - Installation was successful
;                        = 00h - Installation failed
;
; This call is used by external application code  (special screen drivers,
; modem code, database code, etc) to link into the INT 14h service for use
; by multiple applications. The "error return" (BH=0 with AX=1954h) should
; mean that  another application layer has  already been installed at that
; particular code. Codes 80h through BFh should be supported.
;
; External application codes 80h-83h are  reserved by FOSSIL developers for
; re-organizing FOSSIL services by type (comm, screen, keyboard, system).
;
; Installed application code will be entered, via a FAR call, from the INT
; 14H dispatcher whenever it is entered with AH=(application code).
;
; If the value returned in AX from this function is not 1954h, the service
; code that is trying to be installed should bring up its own INT 14h code
; that can service INT 14h functions 7h-BFh (80h-BFh are "applications").
;
;
; AH = 7Fh    Remove an "external application" function
;
;         Parameters:
;             Entry:  AL = Code assigned to external application
;                     DX = Offset of application entry point
;                     ES = Segment of application entry point
;             Exit:   AX = 1954h
;                     BL = Code assigned to application (same as input AL)
;                     BH = 01h - Removal was successful
;                        = 00h - Removal failed
;
; Removes an application's entry into the table.  Usually so it can remove
; itself from memory. Error return means ES:DX did not match or that there
; is no entry at the slot described by AL.
;
; An application that wants to remove itself from memory can issue the  7F
; function to remove itself from the table, then, if it is successful, get
; out of memory. If it had to install itself with an INT 14h dispatcher it
; may back itself out, provided no other applications  have been installed
; on top of it (using its dispatcher).
;
high_funcs:     push ax         ;AX and BX not changed at this point
                push bx
                sub ah,7EH
                jc jump_to_old1
                jz func7E
                dec ah
                jz func7F
                dec ah
                cmp ah,APP_NUM
                jae jump_to_old1
                mov bl,ah
                xor bh,bh
                shl bx,1
                shl bx,1
                mov ax,WORD PTR [app_table+2+bx]
                mov bx,WORD PTR [app_table+0+bx]
                cli
;               f          bp+24      cs
;               cs         bp+22      ip
;               ip         bp+20      segment (ax)
;               -          bp+18      offset (bx)
;               -          bp+16      f
;               push cx    bp+14      cx
;               push dx    bp+12      dx
;               push si    bp+10      si
;               push di    bp+8       di
;               push ds    bp+6       ds
;               push ax    bp+4       ax
;               push bx    bp+2       bx
                push bp   ;bp+0       bp
                mov bp,sp
                mov [bp+18],bx
                xchg ax,[bp+20] ;AX=ip
                xchg ax,[bp+22] ;AX=cs
                xchg ax,[bp+24] ;AX=f
                mov [bp+16],ax
                pop bp
                pop bx
                pop ax
                pop ds
                pop di
                pop si
                pop dx
                pop cx
                popf
                retf

                ALIGN 4


func7E:         mov bx,ax       ;AH=0
                sub al,80H
                jc func7Fb
                cmp al,APP_NUM
                jae func7Fb
                shl ax,1
                shl ax,1
                add ax,OFFSET app_table
                mov si,ax
                mov ax,OFFSET app_none
                mov cx,cs
                cli
                cmp ax,[si]
                jnz func7Fb
                cmp cx,[si+2]
                jnz func7Fb
                mov [si],dx
                mov [si+2],es
                jmp func7Fa

                ALIGN 4

func7F:         mov bx,ax       ;AH=0
                sub al,80H
                jc func7Fb
                cmp al,APP_NUM
                jae func7Fb
                shl ax,1
                shl ax,1
                add ax,OFFSET app_table
                mov si,ax
                mov cx,es
                cli
                cmp dx,[si]
                jnz func7Fb
                cmp cx,[si+2]
                jnz func7Fb
                mov [si],OFFSET app_table
                mov [si+2],cs

func7Fa:        mov bh,1
func7Fb:        sti
                add sp,4        ;Remove extra push ax, push bx
                mov ax,1954H

                ALIGN 4

ret_ax_bx:      pop ds
                pop di
                pop si
                pop dx
                pop cx
                add sp,4
                iret

                ALIGN 4

ret_ax:         pop ds
                pop di
                pop si
                pop dx
                pop cx
                pop bx
                add sp,2
                iret

                ALIGN 4

ret_dx:         pop ds
                pop di
                pop si
                add sp,2
                pop cx
                pop bx
                pop ax
                iret

                ALIGN 4

ret_ax_dx:      pop ds
                pop di
                pop si
                add sp,2
                pop cx
                pop bx
                add sp,2
                iret

                ALIGN 4

app_none:       mov ax,0FFFFH
                retf

                ALIGN 4

ret_none:       pop ds
                pop di
                pop si
                pop dx
                pop cx
                pop bx
                pop ax
timer_iret:     iret

                ALIGN 4

oldinttimer     DD 0
                DB TIMER_INT,'INT'

sysinttimer:    cli
                pushf
                call cs:[oldinttimer]
                cli
                cmp cs:[timer_doing],0
                jnz timer_iret
                mov cs:[timer_doing],1
                sti
                push ax
                push bx
                push cx
                push dx
                push si
                push di
                push ds
                mov ax,cs
                mov ds,ax
                cld
                call read_55ms  ;DX:AX=Count, BX,CX destroyed
                mov bx,[timer_last_l]
                mov cx,[timer_last_h]
                mov [timer_last_l],ax
                mov [timer_last_h],dx
                mov di,65535
                sub ax,bx
                sbb dx,cx
                jnz timer1
                and ax,ax
                jz timer_end
                mov di,ax
timer1:         test [com_config],00000001B
                jnz timer10
timer2:         mov bl,NUM_TIMERS
                mov si,OFFSET timer_calls

                ALIGN 4

timer5:         mov ax,[si]
                or ax,[si+2]
                jz timer7

                mov cx,di

                ALIGN 4

timer6:         call DWORD PTR [si]
                sti
                cld
                loop timer6

timer7:         add si,4
                dec bl
                jnz timer5

timer_end:      cli
                mov [timer_doing],0
                pop ds
                pop di
                pop si
                pop dx
                pop cx
                pop bx
                pop ax
                iret

                ALIGN 4

timer10:        IF POLL_MOD_STAT
                mov dx,[com_base]
                add dx,6                ;Base+6
                in al,dx                ;Modem Status Register
                ELSE
                mov al,[com_modem]
                ENDIF
                and al,al
                mov ax,[timer_watchini] ;Does not change sign flag
                js timer11
                mov ax,[timer_watchcnt]
                sub ax,di
                jbe timer12
timer11:        mov [timer_watchcnt],ax
                jmp timer2
timer12:        jmp reboot

                ALIGN 2

tsr_end         EQU $   ;Must be on even address

txt_doc_init    DB 13,10
                DB 'AnDan Software FOSSIL Version ',VERSION,13,10
                DB 'Copyright (c) 1994-2000 Scandinavian Digital Systems AB',13,10
                DB 13,10
                DB 'Internet: http://www.digsys.se     e-mail: andan@digsys.se',13,10
txt_nl          DB 13,10,0

;
; License text block
;
szLicenseIDMark DB 01AH,0ADH,0DAH,'LIC ID MARK',0ADH,0DAH   ;16 bytes
LicenseIDSize   EQU 16
LicenseTextSize EQU 112   ;Total of 128 bytes
szLicenseText   DB LicenseTextSize DUP(0)
;

txt_doc_free    DB 'Freeware: May be used, copied and distributed if no fee is',13,10
                DB '          charged and if no changes are done.',13,10,0
txt_doc_usage   DB 13,10
                DB 'adf port addr irq baud recbuf[,hold[,cont]] trabuf [fifo] [line] [modem]',13,10
                DB 13,10
                DB 'port    FOSSIL port number, 0-126, or COM-port, COM1-COM127. Example: 0 or COM1',13,10
                DB 'addr    Address in hex of COM-port, 0-FFFF. Example: 3F8',13,10
                DB 'irq     IRQ number of COM-port, 0-15. Example: 4',13,10
                DB 'baud    Locked baud-rate, 1-115200. Example: 38400',13,10
                DB 'recbuf  Size of receive buffer, 256-16384. Example: 8192',13,10
                DB 'hold    Flow control hold or stop, default 7/8 of recbuf. Example: 7168',13,10
                DB 'cont    Flow control continue or restart, default 6/8 of recbuf. Example: 6144',13,10
                DB 'trabuf  Size of transmit buffer, 256-16384. Example: 8192',13,10
                DB 'fifo    Receiver 16550-FIFO trigger level, 1, 4, 8 or 14. Default: 8',13,10
                DB '        Or 16650,rec,tra for setting receiver trigger level 8, 16, 24 or 28,',13,10
                DB '        and transmitter trigger level 8, 16, 24 or 30 on 16650.',13,10
                DB '        Example: 16650,16,8',13,10
                DB '        Or 16750,rec for setting receiver trigger level 1, 16, 32 or 56',13,10
                DB '        on 16750. Example: 16750,32',13,10
                DB 'line    Line control register. Default: 3',13,10
                DB 'modem   Modem control register. Default: 11',13,10
                DB 13,10
                DB 'ADF will stay resident when using the above command line.',13,10
                DB 13,10
                DB 'adf UNLOAD',13,10
                DB 13,10
                DB 'ADF will remove itself from memory when using the above command line.',13,10
                DB 13,10
                DB 'adf watch ON|OFF|time',13,10
                DB 13,10
                DB 'ADF will turn carrier watchdog on or off when using the above command line.',13,10
                DB 'If a numeric value is used, the time out in seconds (10-3600) will be set,',13,10
                DB 'this will not turn the watchdog on or off (default is 60 seconds).',13,10
                DB 0

err_begin       DB 13,10,7,"Error when executing ADF:",13,10,13,10,0
err_end1        DB 13,10,13,10,7,"Press any key to continue, or wait a moment.",0
err_end2        DB 13,10,13,10,0

err_arg         DB 'Argument error (command line error).',0
err_dosver      DB 'DOS v3.1 or newer required.',0
err_tsr         DB 'Unable to handle TSRs in this environment.',0
err_free        DB 'Error when releasing memory.',0
err_baud        DB 'Invalid (not realizable) baud-rate.',0
err_mem         DB 'Not enough memory for buffers.',0
err_intrel      DB 'Error when restoring interrupts.',0
err_reload      DB 'ADF already loaded.',0
err_notload     DB 'ADF not loaded.',0

txt_loaded      DB 13,10,'ADF loaded.',13,10,0
txt_unload      DB 13,10,'ADF unloaded.',13,10,0
str_unload      DB 'UNLOAD'
str_watch       DB 'WATCH'
str_on          DB 'ON'
str_off         DB 'OFF'
txt_watch_on    DB 13,10,'Carrier watchdog is now on',13,10,0
txt_watch_off   DB 13,10,'Carrier watchdog is now off',13,10,0
txt_watch_set   DB 13,10,'Carrier watchdog time out set',13,10,0

                ALIGN 2

pspseg          DW 0

;
; print
;

                ALIGN 2

print:          xor     al,al
                mov     di,si
                mov     cx,0FFFFh
                repne   scasb
                not     cx
                dec     cx
                mov     bx,1
                mov     dx,si
                mov     ah,40H
                int     21H
                ret

                ALIGN 2

;
; print_err
;
print_err:      push ax
                mov ax,cs
                mov ds,ax
                mov es,ax
                push si
                mov si,OFFSET err_begin
                call print
                pop si
                call print
                mov si,OFFSET err_end1
                call print
                mov si,30
                mov ah,2CH
                int 21H
print_err1:     mov bl,dh
print_err2:     mov ah,01H
                int 16H
                jnz print_err4
                mov ah,2CH
                int 21H
                cmp bl,dh
                jz print_err2
                dec si
                jnz print_err1
print_err3:     mov si,OFFSET err_end2
                call print
                pop ax
                ret

print_err4:     xor ah,ah
                int 16H
                jmp print_err3

                ALIGN 2

jmp_white:      lodsb
                cmp     al,13
                je      jmp_white1
                cmp     al,32
                jbe     jmp_white
                dec     si
                clc
                ret
jmp_white1:     dec     si
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
ascdec3:        clc
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

asclong:        push di
                mov di,10
                xor ax,ax
                xor cx,cx
                xor bx,bx
asclong1:       mov cl,[si]
                sub cl,'0'
                jc asclong3
                cmp cl,10
                jae asclong3
                inc si
                xchg bx,ax
                mul di
                xchg bx,ax
                and dx,dx
                jnz asclong2
                mul di
                add ax,cx
                adc bx,dx
                jnc asclong1
asclong2:       pop di
                stc
                ret
asclong3:       mov dx,bx
                pop di
                cmp BYTE PTR [si],33
                cmc
                ret

                ALIGN 2

;
; uldiv
;
; DX:AX = DX:AX / CX:BX
; CX:BX = DX:AX % CX:BX
;
; No other registers changed.
;
uldiv:          jcxz uldiv7
                push bp
                mov bp,1
                and ch,ch
                jnz uldiv1
                add bp,8
                mov ch,cl
                mov cl,bh
                mov bh,bl
                xor bl,bl
                and ch,ch
uldiv1:         js uldiv3
uldiv2:         inc bp
                shl bx,1
                rcl cx,1
                jno uldiv2
uldiv3:         push si
                push di
                mov si,cx
                mov di,bx
                mov cx,dx
                mov bx,ax
                xor ax,ax
                xor dx,dx
uldiv4:         cmp si,cx
                ja uldiv6
                jc uldiv5
                cmp di,bx
                ja uldiv6
uldiv5:         sub bx,di
                sbb cx,si
                stc
uldiv6:         rcl ax,1
                rcl dx,1
                shr si,1
                rcr di,1
                dec bp
                jnz uldiv4
                pop di
                pop si
                pop bp
                ret

                ALIGN 2

uldiv7:         and dx,dx
                jnz uldiv8
                div bx
                mov bx,dx
                mov dx,cx
                ret

                ALIGN 2

uldiv8:         mov cx,ax
                mov ax,dx
                xor dx,dx
                div bx
                xchg cx,ax
                div bx
                mov bx,dx
                mov dx,cx
                xor cx,cx
                ret

                ALIGN 2

doc:            mov si,OFFSET txt_doc_init
                call print
                cmp [szLicenseText],0
                jz doc1
                mov si,OFFSET szLicenseText
                call print
                mov si,OFFSET txt_nl
                jmp print

doc1:           mov si,OFFSET txt_doc_free
                jmp print

                ALIGN 2

;
; int_init
;
; Initialize an interrupt.
;
; In:  DS:BX = Address to the interrupt routine and data. The routine and
;              data must must have the structure:
;
;              oldintXX        DD 0                     ;Nonzero if vector
;                                                       ;already is saved
;                                                       ;Zero if vector
;                                                       ;is not saved
;
;                              DB XXH,'INT'             ;XXH is the interrupt
;                                                       ;number in hex
;
;              intXX           PROC FAR                 ;DS:BX points here
;
;                              .
;                              .
;                              .
;
;              intXX           ENDP
;
;
; Register AX, BX, CX, DX are destroyed
;
; Note, may be called during unload with DS set to TSR.
;
USE_INT21       EQU 1           ;Use INT 21H to modify interrupt pointers

int_init:       mov ax,[bx-8]
                or ax,[bx-6]
                jnz int_init1
                push es

                IFE USE_INT21

                mov cx,di
                mov al,[bx-4]
                xor ah,ah
                shl ax,1
                shl ax,1
                mov di,ax
                xor ax,ax
                mov es,ax
                cli
                mov ax,es:[di]
                mov dx,es:[di+2]
                mov [bx-8],ax
                mov [bx-6],dx
                mov es:[di],bx
                mov es:[di+2],ds
                sti
                mov di,cx

                ELSE

                mov dx,bx
                mov al,[bx-4]
                mov ah,35H
                cli
                int 21H
                cli
                xchg dx,bx
                mov [bx-8],dx
                mov [bx-6],es
                mov dx,bx
                mov ah,25H
                int 21H
                sti

                ENDIF

                pop es

int_init1:      ret


                ALIGN 2

;
; int_term
;
; Restores an interrupt.
;
; In:  DS:BX = Address to the interrupt routine and data, see 'int_init'.
; Out: C = 1 if no restore was possible.
;
; Register AX, BX, CX, DX are destroyed
;
; Note, may be called during unload with DS set to TSR.
;
int_term:       mov ax,[bx-8]
                or ax,[bx-6]
                jz int_term2

                push di
                push es
                mov cx,ds

                IFE USE_INT21

                mov al,[bx-4]
                xor ah,ah
                shl ax,1
                shl ax,1
                mov di,ax
                mov dx,ax
                xor ax,ax
                mov es,ax
                cli
                les di,es:[di]
                mov ax,es
                cmp ax,cx
                jnz int_term4
                cmp di,bx
                jnz int_term4
                xor ax,ax
                mov es,ax
                mov di,dx
                mov ax,[bx-8]
                mov dx,[bx-6]
                mov es:[di],ax
                mov es:[di+2],dx
                xor ax,ax
                mov [bx-8],ax
                mov [bx-6],ax
                sti

                ELSE

                mov dx,bx
                mov al,[bx-4]
                mov ah,35H
                cli
                int 21H
                cli
                mov di,bx
                mov bx,dx
                mov dx,es
                cmp dx,cx
                jnz int_term4
                cmp di,bx
                jnz int_term4
                mov cx,ds
                lds dx,[bx-8]
                mov ah,25H
                int 21H
                cli
                xor ax,ax
                mov es:[bx-8],ax
                mov es:[bx-6],ax
                sti
                mov ds,cx

                ENDIF

int_term1:      pop es
                pop di
int_term2:      clc
                ret

int_term3:      les di,es:[di-8]

;
; BX = Offset to interrupt header to release
; DS = Segment to interrupt header to release
; CX = DS
; DI = Offset to current interrupt header to release
; ES = Segment to current interrupt header to release

int_term4:      cmp di,8
                jb int_term5
                cmp WORD PTR es:[di-2],'TN'
                jnz int_term5
                mov ax,[bx-4]
                cmp ax,es:[di-4]
                jnz int_term5
                cmp bx,es:[di-8]
                jnz int_term3
                cmp cx,es:[di-6]
                jnz int_term3
                mov ax,[bx-8]
                mov cx,[bx-6]
                mov es:[di-8],ax
                mov es:[di-6],cx
                xor ax,ax
                mov [bx-8],ax
                mov [bx-6],ax
                sti
                jmp int_term1

int_term5:      sti
                pop es
                pop di
                stc
                ret

                ALIGN 2

;
; find_tsr
;
; In:   ES = DS = CS
; Out:  ZF = 1 --> TSR not found
;                  DX = 0
;       ZF = 0 --> TSR found
;                  DX = Segment
; Chg:  AX, BX, CX, DX, SI, DI
;
; block_init must have been called once on program startup
;

first_block_seg DW 0

find_tsr:       mov dx,[first_block_seg]

find_tsr1:      call dos_next_block
                and dx,dx
                jz find_tsr2
; DS = DX-1
                cmp dx,ds:[1]
                jnz find_tsr1
                mov si,90H
                mov di,OFFSET tsr_id
                mov cx,tsr_id_len
                repe cmpsb
                jnz find_tsr1

find_tsr2:      mov ax,cs
                mov ds,ax
                and dx,dx
                ret

                ALIGN 2

dos_next_block: and dx,dx
                jz next_block4
                dec dx
                jz next_block4
                mov ds,dx
                inc dx
                mov al,ds:[0]
                cmp al,4DH
                jnz next_block3
                add dx,ds:[3]
                jc next_block3
next_block2:    mov ds,dx
                inc dx
                jz next_block4
                mov al,ds:[0]
                cmp al,4DH
                jz next_block4
                cmp al,5AH
                jz next_block4
next_block3:    xor dx,dx
next_block4:    ret

                ALIGN 2

old_umb         DW 0
exit_flags      DB 0
                DB 0

block_init:     mov ax,5802H
                int 21H
                jnc get_umb1
                xor al,al
get_umb1:       xor ah,ah
                mov [old_umb],ax
                or [exit_flags],00000001B
                mov bx,1        ;UMBs are part of DOS allocated memory block chain
                mov ax,5803H
                int 21H

                mov ah,52H
                int 21H
                mov dx,es:[bx-2]
                inc dx
                push dx
                call block_init_s
                pop ax
                jnz block_init1
                xor ax,ax
                mov es,ax
                mov dx,es:[2EH*4+2]
                push dx
                call block_init_s
                pop ax
                jz block_init2
block_init1:    mov [first_block_seg],ax
                clc
                ret
block_init2:    stc
                ret

block_init_s:   mov cx,1024
block_init_s1:  call dos_next_block
                and dx,dx
                jz block_init_s2
                cmp dx,cs:[pspseg]
                loopnz block_init_s1
block_init_s2:  mov ax,cs
                mov ds,ax
                and dx,dx
                ret

                ALIGN 2

strcmpi:        lodsb
                cmp al,es:[di]
                jz strcmpi1
                sub al,32
                cmp al,es:[di]
                jnz strcmpi2
strcmpi1:       inc di
                loop strcmpi
                clc
                ret
strcmpi2:       stc
                ret

                ALIGN 2

sysint24:       sti
                push ds
                push bx
                push ax
sysint24a:      mov ds,cs:[pspseg]
                pushf
                call DWORD PTR ds:[12H]
                pop bx
                mov ah,bh
                pop bx
                pop ds
                and al,al
                jnz sysint24c
                test ah,00100000B
                jnz sysint24e
                mov al,3
sysint24c:      cmp al,1
                jnz sysint24d
                test ah,00010000B
                jnz sysint24e
                mov al,3
sysint24d:      cmp al,3
                jnz sysint24f
                test ah,00001000B
                jz sysint24f
sysint24e:      iret
sysint24f:      jmp prg_quit

;
; Start of program
;
main:           cld
                mov cs:[pspseg],ds      ;Save PSP segment
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
                xor ax,ax
                mov es,ax
                mov di,22H*4
                mov ax,OFFSET sysint22
                stosw
                mov ax,dx
                stosw
                mov ax,OFFSET sysint23
                stosw
                mov ax,dx
                stosw
                mov ax,OFFSET sysint24
                stosw
                mov ax,dx
                stosw
                sti

                mov es,dx
                mov si,80H
                mov di,OFFSET arg_buf
                mov cl,[si]
                add cl,3
                shr cl,1
                xor ch,ch
                rep movsw
                mov ds,dx

                call doc

                mov ah,30H
                int 21H
                cmp al,3
                jb main3
                ja main4
                cmp ah,1
                jae main4
main3:          mov si,OFFSET err_dosver
                jmp SHORT print_quit_err

main4:          call block_init
                jnc main5

main4a:         mov si,OFFSET err_tsr
                jmp SHORT print_quit_err

main5:          mov ax,cs
                mov es,ax
                mov bx,[pspseg]
                sub ax,bx
                cmp ax,10H
                jnz main4a
                mov si,OFFSET arg_buf+1
                call jmp_white
                jc no_args
                cmp al,'u'
                je main8
                cmp al,'U'
                je main8
                cmp al,'w'
                je main7
                cmp al,'W'
                je main7
                jmp main20

main7:          mov di,OFFSET str_watch
                mov cx,5
                call strcmpi
                jc arg_err
                call jmp_white
                jc arg_err
                jmp SHORT cmd_watch

main8:          mov di,OFFSET str_unload
                mov cx,6
                call strcmpi
                jc arg_err
                jmp cmd_unload

no_args:        mov si,OFFSET txt_doc_usage
                call print
                jmp prg_quit

arg_err:        mov si,OFFSET err_arg

print_quit_err: mov al,0FFH

                call print_err

prg_exit:       push ax
                mov ax,cs
                mov ds,ax
                test [exit_flags],00000001B
                jz prg_exit1
                and [exit_flags],11111110B
                mov bx,[old_umb]
                mov ax,5803H
                int 21H
prg_exit1:      pop ax
                mov ah,4CH
                int 21H

sysint22:
sysint23:
prg_quit:       mov al,0FFH
                jmp prg_exit

print_exit_ok:  mov ax,cs
                mov ds,ax
                mov es,ax
                call print
                xor al,al
                jmp prg_exit

to_not_loaded:  jmp not_loaded

cmd_watch:      push si
                call find_tsr
                pop si
                jz to_not_loaded
                add dx,8
                mov ds,dx
                push ds
                mov dl,[fossil_port]
                xor dh,dh
                mov ax,cs
                mov ds,ax
                push si
                mov di,OFFSET str_on
                mov cx,2
                call strcmpi
                pop si
                jnc cmd_watch1
                push si
                mov di,OFFSET str_off
                mov cx,3
                call strcmpi
                pop si
                jnc cmd_watch2
                push dx
                call ascdec
                pop dx
                pop es
                jc arg_err
                cmp BYTE PTR [si],33
                jnc arg_err
                cmp ax,10
                jb to_arg_err1
                cmp ax,3600
                ja to_arg_err1
                mov bx,182
                mul bx
                add ax,5
                adc dx,0
                mov bx,10
                div bx
                mov es:[timer_watchini],ax
                mov es:[timer_watchcnt],ax
                mov si,OFFSET txt_watch_set
                jmp SHORT print_exit_ok
cmd_watch1:     pop ax
                mov ax,1401h
                int 14H
                mov si,OFFSET txt_watch_on
                jmp print_exit_ok
cmd_watch2:     pop ax
                mov ax,1400H
                int 14H
                mov si,OFFSET txt_watch_off
                jmp print_exit_ok

not_loaded:     mov si,OFFSET err_notload
                jmp print_quit_err

to_arg_err1:    jmp arg_err

cmd_unload:     call find_tsr
                jz not_loaded
                push dx
                add dx,8
                mov ds,dx
                mov dx,[com_base]
                call clearcom
                mov bx,[com_picmsk1]
                in al,021H
                jmp $+2
                and al,bh
                or al,[com_picval1]
                out 021H,al
                mov bx,[com_picmsk2]
                and bx,bx
                jz cmd_unload1
                in al,0A1H
                jmp $+2
                and al,bh
                or al,[com_picval2]
                out 0A1H,al
cmd_unload1:

                sti
                mov bx,OFFSET fossil
                call int_term
                jc intrel_err
                IF USE_TIMER
                mov bx,OFFSET sysinttimer
                call int_term
                jc intrel_err
                ENDIF
                mov bx,OFFSET comint
                call int_term
                jc intrel_err
                pop dx
                mov es,dx
                mov ah,49H
                int 21H
                jc to_free_err
                mov si,OFFSET txt_unload
                jmp print_exit_ok

intrel_err:     mov si,OFFSET err_intrel
                jmp print_quit_err
to_free_err:    jmp free_err

main20:         cmp al,'c'
                jz port11
                cmp al,'C'
                jnz port14
port11:         inc si
                lodsb
                cmp al,'o'
                jz port12
                cmp al,'O'
                jnz to_arg_err2
port12:         lodsb
                cmp al,'m'
                jz port13
                cmp al,'M'
                jnz to_arg_err2
port13:         call ascdec
                jc to_arg_err2
                sub ax,1
                jae port15

to_arg_err2:    jmp arg_err

baud_err:       mov si,OFFSET err_baud
                jmp print_quit_err

port14:         call ascdec
                jc to_arg_err2
port15:         cmp BYTE PTR [si],33
                jnc to_arg_err2
                cmp ax,126
                ja to_arg_err2
                mov [fossil_port],al
                call jmp_white
                jc to_arg_err2
                call aschex
                jc to_arg_err2
                mov [com_base],ax
                call jmp_white
                jc to_arg_err2
                call ascdec
                jc to_arg_err2
                cmp BYTE PTR [si],33
                jnc to_arg_err2
                cmp ax,16
                jae to_arg_err2
                mov [com_irq],al
                call jmp_white
                jc to_arg_err2
                call asclong
                jc to_arg_err2
;
; Divisor = 115200 / Baud
;
                mov cx,dx
                mov bx,ax
                mov dx,00001H           ;115200
                mov ax,0C200H
;
; DX:AX = DX:AX / CX:BX
; CX:BX = DX:AX % CX:BX
;
                call uldiv
;
                and dx,dx
                jnz to_arg_err2
                and ax,ax
                jz to_arg_err2
                mov [com_baud],ax
                or bx,cx
                jnz baud_err
                call jmp_white
                jc to_arg_err2
                call ascdec
                jc to_arg_err2
                cmp ax,256
                jb to_arg_err2
                cmp ax,16384
                ja to_arg_err2
                inc ax                  ;Add one extra to get an even number on
                                        ;FOSSIL info return values (info_ibufr)
                mov [com_reclen],ax
                dec ax
                mov [info_ibufr],ax
                mov cx,ax
                shr ax,1
                shr ax,1
                sub cx,ax
                mov [com_recflcont],cx     ;info_ibufr - info_ibufr/4
                shr ax,1
                add cx,ax
                mov [com_recflhold],cx     ;info_ibufr - info_ibufr/4 + info_ibufr/8

                cmp BYTE PTR [si],','
                jnz flow13
                inc si
                call ascdec
                cmp ax,128
                jb to_arg_err3
                mov cx,[info_ibufr]
                mov bx,cx
                sub cx,16
                cmp ax,cx
                ja to_arg_err3
                mov [com_recflhold],ax
                sub bx,ax
                sub ax,bx
                jc flow11
                cmp ax,64
                jae flow12
flow11:         mov ax,64
flow12:         mov [com_recflcont],ax

                cmp BYTE PTR [si],','
                jnz flow13
                inc si
                call ascdec
                cmp ax,64
                jb to_arg_err3
                mov cx,[com_recflhold]
                sub cx,16
                cmp ax,cx
                ja to_arg_err3
                mov [com_recflcont],ax

flow13:         cmp BYTE PTR [si],33
                jc flow14

to_arg_err3:    jmp arg_err

flow14:         call jmp_white
                jc to_arg_err3
                call ascdec
                jc to_arg_err3
                cmp BYTE PTR [si],33
                jnc to_arg_err3
                cmp ax,256
                jb to_arg_err3
                cmp ax,16384
                ja to_arg_err3
                inc ax                  ;Add one extra to get an even number on
                                        ;FOSSIL info return values (info_obufr)
                mov [com_tralen],ax
                dec ax
                mov [info_obufr],ax

                mov [com_fifoctrl],10000000B    ;FIFO control register (bit 2-0 must be zero)
                mov [com_linectrl],00000011B    ;DLAB=0, 8N1
                mov [com_modemctrl],00001011B   ;Enable IRQ, set RTS and DTR
                mov [com_trafifo1],16           ;Bytes to fill FIFO on transmit hold register empty
                mov [com_trafifo2],16           ;Bytes to fill FIFO on transmit interrupt
                mov [com_enhanced],00000011B    ;DLAB=0, 8N1

                call jmp_white
                jc to_main23
                call ascdec
                jc to_arg_err4
                cmp ax,16650
                jz fifo20
                cmp ax,16750
                jz fifo30
                cmp BYTE PTR [si],33
                jnc to_arg_err4
                and ah,ah
                jnz to_arg_err4
                cmp al,1
                jz to_fifo99
                mov ah,01000000B
                cmp al,4
                jz to_fifo99
                mov ah,10000000B
                cmp al,8
                jz to_fifo99
                mov ah,11000000B
                cmp al,14
                jz to_fifo99

to_arg_err4:    jmp arg_err
to_main23:      jmp main23

fifo30:         or [com_config],00000100B       ;16750
                cmp BYTE PTR [si],','
                jnz to_arg_err4
                inc si
                call ascdec
                cmp BYTE PTR [si],33
                jnc to_arg_err4
                and ah,ah
                jnz to_arg_err4
                mov ah,00100000B
                cmp al,1
                jz fifo31
                mov ah,01100000B
                cmp al,16
                jz fifo31
                mov ah,10100000B
                cmp al,32
                jz fifo31
                mov ah,11100000B
                cmp al,56
                jnz to_arg_err4

fifo31:         IF 0  ;Keep 16 bytes transmit FIFO for 16750
                mov al,64
                mov [com_trafifo1],al           ;Bytes to fill FIFO on transmit hold register empty
                mov [com_trafifo2],al           ;Bytes to fill FIFO on transmit interrupt
                ENDIF

to_fifo99:      jmp SHORT fifo99

fifo20:         or [com_config],00000010B       ;16650
                cmp BYTE PTR [si],','
                jnz to_arg_err4
                inc si
                call ascdec
                and ah,ah
                jnz to_arg_err4
                cmp al,8
                jz fifo21
                mov ah,01000000B
                cmp al,16
                jz fifo21
                mov ah,10000000B
                cmp al,24
                jz fifo21
                mov ah,11000000B
                cmp al,28
                jnz to_arg_err4

fifo21:         mov [com_fifoctrl],ah

                cmp BYTE PTR [si],','
                jnz to_arg_err4
                inc si
                call ascdec
                cmp BYTE PTR [si],33
                jnc to_arg_err4
                and ah,ah
                jnz to_arg_err4
                cmp al,16
                jz fifo22
                mov ah,00010000B
                cmp al,8
                jz fifo22
                mov ah,00100000B
                cmp al,24
                jz fifo22
                mov ah,00110000B
                cmp al,30
                jnz to_arg_err5

fifo22:         or ah,[com_fifoctrl]
                mov cl,32
                mov [com_trafifo1],cl           ;Bytes to fill FIFO on transmit hold register empty
                sub cl,al
                mov [com_trafifo2],cl           ;Bytes to fill FIFO on transmit interrupt

fifo99:         mov [com_fifoctrl],ah

line10:         call jmp_white
                jc main23
                call ascdec
                jc to_arg_err5
                cmp BYTE PTR [si],33
                jnc to_arg_err5
                and al,00111111B
                mov [com_linectrl],al
                call jmp_white
                jc main23
                call ascdec
                jc to_arg_err5
                cmp BYTE PTR [si],33
                jnc to_arg_err5
                mov [com_modemctrl],al
                call jmp_white
                jc main23

to_arg_err5:    jmp arg_err

main23:         mov ax,0001000010111111B        ;Enhanced Feature Register
                test [com_config],00000010B     ;16650
                jnz accenh1
                mov al,[com_linectrl]
                or al,10000000B                 ;DLAB=1
                mov ah,[com_fifoctrl]
                or ah,00000111B                 ;RCVR trigger level, Reset FIFO
                test [com_config],00000100B     ;16750
                jnz accenh1
                mov al,[com_linectrl]
accenh1:        mov [com_enhanced],ax

                call find_tsr
                jz main24
                mov si,OFFSET err_reload
                jmp print_quit_err

free_err:       mov si,OFFSET err_free
                jmp print_quit_err

main24:         mov es,[pspseg]
                mov es,es:[2CH]
                mov ah,49H
                int 21H
                jc free_err

                call read_55ms  ;DX:AX=Count, BX,CX destroyed
                mov [timer_last_l],ax
                mov [timer_last_h],dx
                mov ax,1092             ;60 s
                mov [timer_watchini],ax
                mov [timer_watchcnt],ax

                mov cl,[com_irq]
                cmp cl,8
                jb picmask1a
                mov cl,2
picmask1a:      inc cl
                xor al,al
                stc
                rcl al,cl
                mov ah,al
                not ah
                mov [com_picmsk1],ax
                xor ax,ax
                mov cl,[com_irq]
                sub cl,8
                jb picmask2a
                inc cl
                stc
                rcl al,cl
                mov ah,al
                not ah
picmask2a:      mov [com_picmsk2],ax

                xor di,di
                xor si,si
                mov ax,[pspseg]
                add ax,8
                mov es,ax
                mov cx,OFFSET tsr_end
                shr cx,1
                rep movsw
;
; TSR portion moved, do not call functions or access data in TSR portion
; of EXE segment.
;
                mov ds,ax
;
; DS = ES = TSR memory
;
                mov cx,APP_NUM
                mov di,OFFSET app_table
                mov si,ds

                mov [info_ident_s],si

                ALIGN 2

main24a:        mov ax,OFFSET app_none
                stosw
                mov ax,si
                stosw
                loop main24a

                mov ax,OFFSET tsr_end
                mov [com_recstart],ax
                mov [com_rec],ax
                mov [com_recint],ax
                add ax,[info_ibufr]     ;[com_reclen]-1
                mov [com_recend],ax
                inc ax
                mov [com_trastart],ax   ;= com_reclim
                mov [com_tra],ax
                mov [com_traint],ax
                add ax,[info_obufr]     ;[com_tralen]-1
                mov [com_traend],ax
                inc ax
                mov [com_tralim],ax     ;= First free byte of program
                add ax,15+128   ;Include PSP
                mov cl,4
                shr ax,cl
                cmp ax,10H
                jnc main26
                mov ax,10H

main26:         mov cx,cs
                mov es,cs:[pspseg]
                sub cx,es:[2]
                neg cx
                cmp ax,cx
                ja mem_err
                push ax                 ;Mem size
                mov bx,OFFSET comint
                mov al,[com_irq]
                add al,8
                cmp al,10H
                jb main27
                add al,60H
main27:         mov [bx-4],al
                call int_init
                IF USE_TIMER
                mov bx,OFFSET sysinttimer
                call int_init
                ENDIF
                mov bx,OFFSET fossil
                call int_init

                cli
                mov bx,[com_picmsk1]
                in al,21H
                and al,bl
                mov [com_picval1],al

                mov bx,[com_picmsk2]
                and bx,bx
                jz picmask2b
                in al,0A1H
                and al,bl
                mov [com_picval2],al
picmask2b:      sti

                mov dl,[fossil_port]
                xor dh,dh
                mov ah,1CH
                int 14H

                mov ax,cs
                mov ds,ax
                mov es,ax
                mov si,OFFSET txt_loaded
                call print

                test [exit_flags],00000001B
                jz main28
                and [exit_flags],11111110B
                mov bx,[old_umb]
                mov ax,5803H
                int 21H
main28:         pop dx                  ;Mem size
                mov ax,3100H
                int 21H
                jmp prg_quit

mem_err:        mov si,OFFSET err_mem
                jmp print_quit_err

PROG            ENDS

DATA            SEGMENT PARA PUBLIC 'DATA'

arg_buf         DB 128 DUP(?)

DATA            ENDS

STACK           SEGMENT PARA STACK 'STACK'

                DB 2048 DUP(?)

STACK           ENDS

                END main
