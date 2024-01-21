;
; adfdebug.asm  January 19, 2000
;
; Copyright (c) 1995-2000 Scandinavian Digital Systems AB
;
;
; Note, MASM v6.11 cannot use "ASSUME CS:", and OFFSET always gives the
; offset to labels segment or group, no segment override is available.
; This makes it hard to write efficient TSR COM-programs, so this program
; is an EXE-program.
;

                INCLUDE <adf.inc>

EXE             GROUP TSRCODE, TSRDATA, PROG, DATA, STACK

                ASSUME DS:EXE, ES:EXE, SS:EXE

INT14_MAXFUNC   EQU 21H

TSRCODE         SEGMENT PARA PUBLIC 'CODE'

; The TSR starts at offset 0

tsr_id          DB 0,13

info_string     DB 'AnDan Software FOSSIL Debug Version ',VERSION
                DB 0

tsr_id_len      EQU $-tsr_id

                ALIGN 2

debug_mode      DB 0    ; =0 --> No output
                        ; =1 --> Output on screen
                        ; =2 --> Output on file

debug_timer     DB 0    ; =1 --> Timing mode

debug_sep       DB 0    ; =0 --> CR, LF
                        ; !=0 --> character

                ALIGN 2

DebFileName     DB 32 DUP(0)

DebBuf          DB 1024 DUP(0)

DebTxtNone      DB 'Nothing',0

                ALIGN 2

OffSP           EQU 32
RegCS           EQU 28
RegIP           EQU 26
RegF            EQU 18
RegAX           EQU 16
RegBX           EQU 14
RegCX           EQU 12
RegDX           EQU 10
RegBP           EQU 8
RegSI           EQU 6
RegDI           EQU 4
RegDS           EQU 2
RegES           EQU 0

RegAH           EQU 17
RegAL           EQU 16
RegBH           EQU 15
RegBL           EQU 14
RegCH           EQU 13
RegCL           EQU 12
RegDH           EQU 11
RegDL           EQU 10

DebRegStart     LABEL WORD

Deb16Reg18      DW 0
Deb16Reg16      LABEL WORD
Deb8Reg16       DB 0
Deb8Reg17       DB 0
Deb16Reg14      LABEL WORD
Deb8Reg14       DB 0
Deb8Reg15       DB 0
Deb16Reg12      LABEL WORD
Deb8Reg12       DB 0
Deb8Reg13       DB 0
Deb16Reg10      LABEL WORD
Deb8Reg10       DB 0
Deb8Reg11       DB 0
Deb16Reg8       DW 0
Deb16Reg6       DW 0
Deb16Reg4       DW 0
Deb16Reg2       DW 0
Deb16Reg0       DW 0

DebRegLen       EQU $-DebRegStart

Deb16RS16       DB 'AX'
Deb8RS16        DB 'AL'
Deb8RS17        DB 'AH'
Deb16RS14       DB 'BX'
Deb8RS14        DB 'BL'
Deb8RS15        DB 'BH'
Deb16RS12       DB 'CX'
Deb8RS12        DB 'CL'
Deb8RS13        DB 'CH'
Deb16RS10       DB 'DX'
Deb8RS10        DB 'DL'
Deb8RS11        DB 'DH'
Deb16RS8        DB 'BP'
Deb16RS6        DB 'SI'
Deb16RS4        DB 'DI'
Deb16RS2        DB 'DS'
Deb16RS0        DB 'ES'


DebStr          MACRO str1:REQ
                LOCAL strlbl1
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                ENDM

DebSep          MACRO
                call _DebSep
                ENDM

DebStrNone      MACRO
                mov si,OFFSET DebTxtNone
                call DebText
                call _DebSep
                ENDM

                IF 0    ;Not used

Deb8            MACRO str1:REQ,reg:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov [@CatStr(Deb8Reg,%reg)],-1
                mov al,[bp+reg]
                call DebBinHex8
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

Deb16           MACRO str1:REQ,reg:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov [@CatStr(Deb16Reg,%reg)],-1
                mov ax,[bp+reg]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

Deb32           MACRO str1:REQ,reg1:REQ,reg2:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov [@CatStr(Deb16Reg,%reg1)],-1
                mov ax,[bp+reg1]
                call DebBinHex16
                mov al,':'
                stosb
                mov [@CatStr(Deb16Reg,%reg2)],-1
                mov ax,[bp+reg2]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

                ENDIF   ;Not used

DebCSIP         MACRO str1:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov ax,[bp+RegCS]
                call DebBinHex16
                mov al,':'
                stosb
                mov ax,[bp+RegIP]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

DebSSSP         MACRO str1:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov ax,ss
                call DebBinHex16
                mov al,':'
                stosb
                mov ax,bp
                add ax,OffSP
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

DebFlags        MACRO str1:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
                IFNB <str2>
strlbl2         DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET strlbl1
                call DebText
                mov ax,[bp+RegF]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

DebOth16        MACRO str1:REQ,reg:REQ
                LOCAL strlbl1,skip
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
TSRDATA         ENDS
                cmp [@CatStr(Deb16Reg,%reg)],0
                jnz skip
                mov si,OFFSET strlbl1
                call DebText
                mov ax,[bp+reg]
                call DebBinHex16
skip:
                ENDM

DebOth8         MACRO str1:REQ,str2:REQ,str3:REQ,reg1:REQ,reg2:REQ,reg3:REQ
                LOCAL strlbl1,strlbl2,strlbl3,oth1,oth2,oth3
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl1         DB str1
                DB 0
strlbl2         DB str2
                DB 0
strlbl3         DB str3
                DB 0
TSRDATA         ENDS
                cmp [@CatStr(Deb16Reg,%reg1)],0
                jnz oth1
                mov si,OFFSET strlbl1
                call DebText
                mov ax,[bp+reg1]
                call DebBinHex16
                jmp oth3
oth1:           cmp [@CatStr(Deb8Reg,%reg2)],0
                jnz oth2
                mov si,OFFSET strlbl2
                call DebText
                mov al,[bp+reg2]
                call DebBinHex8
oth2:           cmp [@CatStr(Deb8Reg,%reg3)],0
                jnz oth3
                mov si,OFFSET strlbl3
                call DebText
                mov al,[bp+reg3]
                call DebBinHex8
oth3:
                ENDM

Deb8s           MACRO reg:REQ,str2
                LOCAL strlbl2
                IFNB <str2>
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl2         DB '   '
                DB str2
                DB 0
TSRDATA         ENDS
                ENDIF
                mov si,OFFSET @CatStr(Deb8RS,%reg)
                lodsw
                stosw
                mov al,'='
                stosb
                mov [@CatStr(Deb8Reg,%reg)],-1
                mov al,[bp+reg]
                call DebBinHex8
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

Deb16s          MACRO reg:REQ,str2
                LOCAL strlbl2
                IFNB <str2>
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
strlbl2         DB ' '
                DB str2
                DB 0
TSRDATA         ENDS
                ENDIF
                mov si,OFFSET @CatStr(Deb16RS,%reg)
                lodsw
                stosw
                mov al,'='
                stosb
                mov [@CatStr(Deb16Reg,%reg)],-1
                mov ax,[bp+reg]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

Deb32s          MACRO reg1:REQ,reg2:REQ,str2
                LOCAL strlbl1,strlbl2
TSRDATA         SEGMENT WORD PUBLIC 'CODE'
                IFNB <str2>
strlbl2         DB ' '
                DB str2
                DB 0
                ENDIF
TSRDATA         ENDS
                mov si,OFFSET @CatStr(Deb16RS,%reg1)
                lodsw
                stosw
                mov al,':'
                stosb
                mov si,OFFSET @CatStr(Deb16RS,%reg2)
                lodsw
                stosw
                mov al,'='
                stosb
                mov [@CatStr(Deb16Reg,%reg1)],-1
                mov ax,[bp+reg1]
                call DebBinHex16
                mov al,':'
                stosb
                mov [@CatStr(Deb16Reg,%reg2)],-1
                mov ax,[bp+reg2]
                call DebBinHex16
                IFNB <str2>
                mov si,OFFSET strlbl2
                call DebText
                ENDIF
                ENDM

DebBinHex16:    mov dh,al
                mov al,ah
                call DebBinHex8
                mov al,dh

DebBinHex8:     mov dl,al
                ror al,1
                ror al,1
                ror al,1
                ror al,1
                call DebBinHex4
                mov al,dl

DebBinHex4:     and al,15
                add al,48
                cmp al,58
                jc DebBinHex4a
                add al,7
DebBinHex4a:    stosb
DebText1:       ret

                ALIGN 4

DebText:        lodsb
                and al,al
                jz DebText1
                stosb
                jmp DebText

                ALIGN 4

_DebSep:        mov al,[debug_sep]
                and al,al
                jnz _DebSep1
                mov al,13
                stosb
                mov al,10
_DebSep1:       stosb
                ret

                ALIGN 2

DebOutput:      cmp [debug_mode],2
                jz DebOutput2

                mov ah,0FH
                int 10H               ;Get video mode, active page, num col
                mov bl,3
                mov cx,di
                mov ah,0EH

                ALIGN 2

DebOutput1:     lodsb
                int 10H
                loop DebOutput1
                ret

                ALIGN 2

DebOutput2:     mov dx,OFFSET DebFileName
                mov ax,3D02H
                int 21H
                jnc DebOutput3
                cmp ax,2
                jnz DebOutput5
                xor cx,cx
                mov ah,3CH
                int 21H
                jc DebOutput5
DebOutput3:     mov bx,ax
                xor cx,cx
                xor dx,dx
                mov ax,4202H
                int 21H
                jc DebOutput4
                mov dx,si
                mov cx,di
                mov ah,40H
                int 21H
DebOutput4:     mov ah,3EH
                int 21H
DebOutput5:     ret

                ALIGN 4

DebOthers:      DebStr 'Other regs:'
                DebOth8 ' AX=',' AH=',' AL=',RegAX,RegAH,RegAL
                DebOth8 ' BX=',' BH=',' BL=',RegBX,RegBH,RegBL
                DebOth8 ' CX=',' CH=',' CL=',RegCX,RegCH,RegCL
                DebOth8 ' DX=',' DH=',' DL=',RegDX,RegDH,RegDL
                DebOth16 ' SI=',RegSI
                DebOth16 ' DI=',RegDI
                DebOth16 ' BP=',RegBP
                DebOth16 ' DS=',RegDS
                DebOth16 ' ES=',RegES
                DebFlags ' FLAGS='
                DebSep
                ret

                ALIGN 4

;
; read_838ns
;
; In:  ----
; Out: DX:AX = Value of the free running 838 ns counter.
;
; Registers destroyed: Flags only
;
; Before using, call 'init_838ns' once for initialization.
;
; After using, call 'term_838ns' once for termination.
;
; Each time unit is exactly:
;
; 1/(14318180/12) s = 838.095 ns
;
; When 'read_838ns' is used, the timer channel 0 will be programmed to mode 2
; instead of the standard mode 3, at initialization.
;
; This reprogramming may cause the internal DOS clock to be inaccurate,
; if the program is executed many times (probably about a million times to get
; a few seconds error).
;
; The reprogramming may also cause incompatible problems for other programs,
; depending on mode 3 for channel 0 in the timer IC.
;
; When the program terminates, the timer IC is not reprogrammed to mode 3.
;

ustimer         DB 0

tick_55ms       DW 0

                ALIGN 4

oldint08us      DD 0
                DB 08H,'INT'

sysint08us      PROC FAR

                cli
                cmp cs:[ustimer],0
                jnz sysint08us1
                push ax
                mov al,00110100B        ;Timer 0, Mode 2, 2 byte R/W, Binary
                out 43h,al
                xor al,al
                jmp $+2
                out 40h,al
                jmp $+2
                out 40h,al
                pop ax
                mov cs:[ustimer],255
sysint08us1:    inc cs:[tick_55ms]
                jmp cs:[oldint08us]

sysint08us      ENDP

                ALIGN 4

read_838ns:     mov al,00000100B
                cli
                out 043H,al
                jmp $+2
                in al,040H          ;Read LSB
                jmp $+2
                mov ah,al
                in al,040H          ;Read MSB
                xchg al,ah
                mov dx,cs:[tick_55ms]
                sti
                cmp ax,65535-20
                jb read_838ns1
                cmp dx,cs:[tick_55ms]
                jz read_838ns1
                inc dx
read_838ns1:    not ax              ;timer in DX:AX
                ret

                ALIGN 4

ltoa_tab        DD 1000000000
                DD 100000000
                DD 10000000
                DD 1000000
                DD 100000
                DD 10000
                DD 1000
                DD 100
                DD 10
                DD 1
;
; ltoa  (fixed length, space fill)
;
; In:  DX:AX = 32 bit unsigned integer
;      DS:DI = 10 bytes buffer
;
ltoa:           mov cx,10*256+' '
                mov si,OFFSET ltoa_tab

                ALIGN 4

ltoa1:          xor bl,bl
ltoa2:          sub ax,[si]
                sbb dx,[si+2]
                jc ltoa3
                inc bl
                jmp ltoa2

                ALIGN 4

ltoa3:          add ax,[si]
                adc dx,[si+2]
                add si,4
                and bl,bl
                jz ltoa6
ltoa4:          mov cl,'0'
                or bl,cl
ltoa5:          mov [di],bl
                inc di
                dec ch
                jnz ltoa1
                ret

                ALIGN 4

ltoa6:          cmp ch,1
                jz ltoa4
                mov bl,cl
                jmp ltoa5

                ALIGN 4

func_entry00:   Deb8s RegAH,'Set communications parameters'
                DebSep
                Deb8s RegAL,'Baud rate and param code'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit00:    Deb16s RegAX,'Status'
                DebSep
                ret

                ALIGN 4

func_entry01:   Deb8s RegAH,'Transmit character and wait'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit01:    Deb16s RegAX,'Status'
                DebSep
                ret

                ALIGN 4

func_entry02:   Deb8s RegAH,'Get received character with wait'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit02:    Deb8s RegAH,'Line status'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                ret

                ALIGN 4

func_entry03:   Deb8s RegAH,'Return serial port status'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit03:    Deb16s RegAX,'Status'
                DebSep
                ret

                ALIGN 4

func_entry04:   Deb8s RegAH,'Activate port'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit04:    Deb16s RegAX,'Reply 1954'
                DebSep
                Deb8s RegBH,'Rev of FOSSIL'
                DebSep
                Deb8s RegBL,'Max function number'
                DebSep
                ret

                ALIGN 4

func_entry05:   Deb8s RegAH,'Deactivate port'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit05:    DebStrNone
                ret

                ALIGN 4

func_entry06:   Deb8s RegAH,'Raise/lower DTR'
                DebSep
                Deb8s RegAL,'Raise (01) or lower (00)'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit06:    DebStrNone
                ret

                ALIGN 4

func_entry07:   Deb8s RegAH,'Return timer tick information'
                DebSep
                ret

                ALIGN 4

func_exit07:    Deb8s RegAH,'Ticks per second'
                DebSep
                Deb8s RegAL,'Interrupt number'
                DebSep
                Deb16s RegDX,'Milliseconds per tick'
                DebSep
                ret

                ALIGN 4

func_entry08:   Deb8s RegAH,'Flush output buffer'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit08:    DebStrNone
                ret

                ALIGN 4

func_entry09:   Deb8s RegAH,'Purge output buffer'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit09:    DebStrNone
                ret

                ALIGN 4

func_entry0A:   Deb8s RegAH,'Purge input buffer'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit0A:    DebStrNone
                ret

                ALIGN 4

func_entry0B:   Deb8s RegAH,'Transmit no wait'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit0B:    Deb16s RegAX,'OK (0001) or no room in buffer (0000)'
                DebSep
                ret

                ALIGN 4

func_entry0C:   Deb8s RegAH,'Non-destructive read-ahead'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit0C:    Deb16s RegAX,'Character or FFFF'
                DebSep
                ret

                ALIGN 4

func_entry0D:   Deb8s RegAH,'Keyboard read without wait'
                DebSep
                ret

                ALIGN 4

func_exit0D:    Deb16s RegAX,'Scan code or FFFF'
                DebSep
                ret

                ALIGN 4

func_entry0E:   Deb8s RegAH,'Keyboard read with wait'
                DebSep
                ret

                ALIGN 4

func_exit0E:    Deb16s RegAX,'Scan code'
                DebSep
                ret

                ALIGN 4

func_entry0F:   Deb8s RegAH,'Flow control for serial I/O'
                DebSep
                Deb8s RegAL,'Control bits'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit0F:    DebStrNone
                ret

                ALIGN 4

func_entry10:   Deb8s RegAH,'Control-C / Control-K checking'
                DebSep
                Deb8s RegAL,'Control bits'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit10:    Deb16s RegAX,'Control-C/K received (0001) or not received (0000)'
                DebSep
                ret

                ALIGN 4

func_entry11:   Deb8s RegAH,'Set current cursor location'
                DebSep
                Deb8s RegDH,'Row'
                DebSep
                Deb8s RegDL,'Line'
                DebSep
                ret

                ALIGN 4

func_exit11:    DebStrNone
                ret

                ALIGN 4

func_entry12:   Deb8s RegAH,'Read current cursor location'
                DebSep
                ret

                ALIGN 4

func_exit12:    Deb8s RegDH,'Row'
                DebSep
                Deb8s RegDL,'Line'
                DebSep
                ret

                ALIGN 4

func_entry13:   Deb8s RegAH,'Single character ANSI write to screen'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                ret

                ALIGN 4

func_exit13:    DebStrNone
                ret

                ALIGN 4

func_entry14:   Deb8s RegAH,'Enable or disable the DCD watchdog'
                DebSep
                Deb8s RegAL,'Enable (01) or disable (00)'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit14:    DebStrNone
                ret

                ALIGN 4

func_entry15:   Deb8s RegAH,'Write character to screen using BIOS'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                ret

                ALIGN 4

func_exit15:    DebStrNone
                ret

                ALIGN 4

func_entry16:   Deb8s RegAH,'Add or delete a routine from the timer tick'
                DebSep
                Deb8s RegAL,'Add (01) or delete (00)'
                DebSep
                Deb32s RegES,RegDX,'Address of function'
                DebSep
                ret

                ALIGN 4

func_exit16:    Deb16s RegAX,'OK (0000 or ticks/sec) or fail (FFFF)'
                DebSep
                ret

                ALIGN 4

func_entry17:   Deb8s RegAH,'Reboot system'
                DebSep
                Deb8s RegAL,'Cold (00) or warm (01)'
                DebSep
                ret

                ALIGN 4

func_exit17:    DebStrNone
                ret

                ALIGN 4

func_entry18:   Deb8s RegAH,'Block Read'
                DebSep
                Deb32s RegES,RegDI,'Address of buffer'
                DebSep
                Deb16s RegCX,'Number of bytes'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit18:    Deb16s RegAX,'Bytes transferred'
                DebSep
                ret

                ALIGN 4

func_entry19:   Deb8s RegAH,'Block Write'
                DebSep
                Deb32s RegES,RegDI,'Address of buffer'
                DebSep
                Deb16s RegCX,'Number of bytes'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit19:    Deb16s RegAX,'Bytes transferred'
                DebSep
                ret

                ALIGN 4

func_entry1A:   Deb8s RegAH,'Break begin or end'
                DebSep
                Deb8s RegAL,'Begin (01) or end (00)'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1A:    DebStrNone
                ret

                ALIGN 4

func_entry1B:   Deb8s RegAH,'Return information about FOSSIL'
                DebSep
                Deb32s RegES,RegDI,'Address of buffer'
                DebSep
                Deb16s RegCX,'Number of bytes'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1B:    Deb16s RegAX,'Bytes transferred'
                DebSep
                ret

                ALIGN 4

func_entry1C:   Deb8s RegAH,'Activate port'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1C:    Deb16s RegAX,'Reply 1954'
                DebSep
                Deb8s RegBH,'Rev of FOSSIL'
                DebSep
                Deb8s RegBL,'Max function number'
                DebSep
                ret

                ALIGN 4

func_entry1D:   Deb8s RegAH,'Deactivate port'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1D:    DebStrNone
                ret

                ALIGN 4

func_entry1E:   Deb8s RegAH,'Extended line control initialization'
                DebSep
                Deb8s RegAL,'Break begin (01) or break end (00)'
                DebSep
                Deb16s RegBX,'Parameters'
                DebSep
                Deb16s RegCX,'Parameters'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1E:    Deb16s RegAX,'Status'
                DebSep
                ret

                ALIGN 4

func_entry1F:   Deb8s RegAH,'Extended serial port status/control'
                DebSep
                Deb8s RegAL,'Read (00) or write (01)'
                DebSep
                Deb8s RegBL,'Modem control register'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit1F:    Deb16s RegAX,'Status'
                DebSep
                Deb8s RegBL,'Modem control register'
                DebSep
                ret

                ALIGN 4

func_entry20:   Deb8s RegAH,'Read with no wait (destructive)'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret

                ALIGN 4

func_exit20:    Deb16s RegAX,'Character or FFFF'
                DebSep
                ret

                ALIGN 4

func_entry21:   Deb8s RegAH,'Stuff/Poke the receive buffer'
                DebSep
                Deb8s RegAL,'Character'
                DebSep
                Deb16s RegDX,'Port'
                DebSep
                ret
func_exit21:    DebStrNone
                ret

                ALIGN 4

func_entry_x:   Deb8s RegAH,'Unknown'
                DebSep
func_exit_x:    DebStr 'Unknown'
                DebSep
                ret

                ALIGN 4

func_entry      DW OFFSET func_entry00
                DW OFFSET func_entry01
                DW OFFSET func_entry02
                DW OFFSET func_entry03
                DW OFFSET func_entry04
                DW OFFSET func_entry05
                DW OFFSET func_entry06
                DW OFFSET func_entry07
                DW OFFSET func_entry08
                DW OFFSET func_entry09
                DW OFFSET func_entry0A
                DW OFFSET func_entry0B
                DW OFFSET func_entry0C
                DW OFFSET func_entry0D
                DW OFFSET func_entry0E
                DW OFFSET func_entry0F
                DW OFFSET func_entry10
                DW OFFSET func_entry11
                DW OFFSET func_entry12
                DW OFFSET func_entry13
                DW OFFSET func_entry14
                DW OFFSET func_entry15
                DW OFFSET func_entry16
                DW OFFSET func_entry17
                DW OFFSET func_entry18
                DW OFFSET func_entry19
                DW OFFSET func_entry1A
                DW OFFSET func_entry1B
                DW OFFSET func_entry1C
                DW OFFSET func_entry1D
                DW OFFSET func_entry1E
                DW OFFSET func_entry1F
                DW OFFSET func_entry20
                DW OFFSET func_entry21
                DW OFFSET func_entry_x

func_exit       DW OFFSET func_exit00
                DW OFFSET func_exit01
                DW OFFSET func_exit02
                DW OFFSET func_exit03
                DW OFFSET func_exit04
                DW OFFSET func_exit05
                DW OFFSET func_exit06
                DW OFFSET func_exit07
                DW OFFSET func_exit08
                DW OFFSET func_exit09
                DW OFFSET func_exit0A
                DW OFFSET func_exit0B
                DW OFFSET func_exit0C
                DW OFFSET func_exit0D
                DW OFFSET func_exit0E
                DW OFFSET func_exit0F
                DW OFFSET func_exit10
                DW OFFSET func_exit11
                DW OFFSET func_exit12
                DW OFFSET func_exit13
                DW OFFSET func_exit14
                DW OFFSET func_exit15
                DW OFFSET func_exit16
                DW OFFSET func_exit17
                DW OFFSET func_exit18
                DW OFFSET func_exit19
                DW OFFSET func_exit1A
                DW OFFSET func_exit1B
                DW OFFSET func_exit1C
                DW OFFSET func_exit1D
                DW OFFSET func_exit1E
                DW OFFSET func_exit1F
                DW OFFSET func_exit20
                DW OFFSET func_exit21
                DW OFFSET func_exit_x

                ALIGN 4

jump_to_old:    pop es
                pop ds
                pop di
                pop si
                pop bp
                pop dx
                pop cx
                pop bx
                pop ax
                popf
                pop ax
                pop ax
                pop ax
                jmp cs:[oldint14]

                ALIGN 4

oldint14        DD 0
                DB 14H,'INT'

fossil:         jmp SHORT fossil1

                DB 'ADF',0
                DW 1954H
                DB INT14_MAXFUNC
                DB 0


;               SP          ;BP+32
;               Flags       ;BP+30
;               CS          ;BP+28
;               IP          ;BP+26
fossil1:        push ax     ;BP+24      (timer MSB)
                push ax     ;BP+22      (timer LSB)
                push ax     ;BP+20      (exit func)
                pushf       ;BP+18
                push ax     ;BP+16
                push bx     ;BP+14
                push cx     ;BP+12
                push dx     ;BP+10
                push bp     ;BP+8
                push si     ;BP+6
                push di     ;BP+4
                push ds     ;BP+2
                push es     ;BP+0
                cld
                sti
                mov bp,sp
                mov bx,cs   ;Keep AH
                mov ds,bx
                mov es,bx
                cmp [debug_mode],0
                jz jump_to_old
                mov bx,[bp+30]
                mov [bp+18],bx
                cmp ah,INT14_MAXFUNC
                jbe fossil1a
                mov ah,INT14_MAXFUNC+1
fossil1a:       mov al,ah
                xor ah,ah
                shl ax,1
                mov bx,ax
                mov [bp+20],bx
                xor ax,ax
                mov cx,DebRegLen/2
                mov di,OFFSET DebRegStart
                rep stosw
                mov di,OFFSET DebBuf
                DebStr <'INT 14'>
                DebSep
                mov bx,[bp+20]
                call [func_entry+bx]
                DebCSIP 'CS:IP='
                DebSSSP ' SS:SP='
                DebSep
                call DebOthers
                mov si,OFFSET DebBuf
                sub di,si
                call DebOutput
                cmp [debug_timer],0
                jz fossil2
                call read_838ns
                mov [bp+22],ax
                mov [bp+24],dx
fossil2:        pop es
                pop ds
                pop di
                pop si
                pop bp
                pop dx
                pop cx
                pop bx
                pop ax
                popf
                pushf
                cli
                call cs:[oldint14]
                pushf       ;BP+18
                cli
                push ax     ;BP+16
                push bx     ;BP+14
                push cx     ;BP+12
                push dx     ;BP+10
                push bp     ;BP+8
                push si     ;BP+6
                push di     ;BP+4
                push ds     ;BP+2
                push es     ;BP+0
                mov bp,sp
                mov ax,cs
                mov ds,ax
                mov es,ax
                cmp [debug_timer],0
                jz fossil3
                call read_838ns
                sub ax,[bp+22]
                sbb dx,[bp+24]
                mov [bp+22],ax
                mov [bp+24],dx
fossil3:        sti
                cld
                xor ax,ax
                mov cx,DebRegLen/2
                mov di,OFFSET DebRegStart
                rep stosw
                mov di,OFFSET DebBuf
                DebStr 'Return'
                cmp [debug_timer],0
                jz fossil4
                DebStr ', time: '
                mov ax,[bp+22]
                mov dx,[bp+24]
                call ltoa
fossil4:        DebSep
                mov bx,[bp+20]
                call [func_exit+bx]
                call DebOthers
                mov al,13
                stosb
                mov al,10
                stosb
                mov si,OFFSET DebBuf
                sub di,si
                call DebOutput
                mov ax,[bp+18]
                mov [bp+30],ax
                pop es
                pop ds
                pop di
                pop si
                pop bp
                pop dx
                pop cx
                pop bx
                pop ax
                add sp,8
                iret

TSRCODE         ENDS

PROG            SEGMENT WORD PUBLIC 'CODE'

tsr_end         EQU $   ;Must be on even address

txt_doc_init    DB 13,10
                DB 'AnDan Software FOSSIL Debug Version ',VERSION,13,10
                DB 'Copyright (c) 1995-2000 Scandinavian Digital Systems AB',13,10
                DB 13,10
                DB 'Internet: http://www.digsys.se     e-mail: andan@digsys.se',13,10
                DB 13,10
                DB 'Freeware: May be used, copied and distributed if no fee is',13,10
                DB '          charged and if no changes are done.',13,10
                DB 0

txt_doc_usage   DB 13,10
                DB 'adfdebug command',13,10
                DB 13,10
                DB 39,'command',39,' is one of the following commands:',13,10
                DB 13,10
                DB 'L [opt] Load TSR, should be done after the FOSSIL load. Options:',13,10
                DB '        /t    Use time measurement.',13,10
                DB '        /sNN  Use ASCII NN as separator, default is 13 and 10 (CR and LF).',13,10
                DB 'U       Unload TSR, should be done before the FOSSIL unload.',13,10
                DB 'N       No output (default at load time).',13,10
                DB 'S       Screen output.',13,10
                DB 'F file  File output to the specified file.',13,10
                DB 0

err_begin       DB 13,10,7,"Error when executing ADFDebug:",13,10,13,10,0
err_end1        DB 13,10,13,10,7,"Press any key to continue, or wait a moment.",0
err_end2        DB 13,10,13,10,0

err_arg         DB 'Argument error (command line error).',0
err_dosver      DB 'DOS v3.1 or newer required.',0
err_tsr         DB 'Unable to handle TSRs in this environment.',0
err_free        DB 'Error when releasing memory.',0
err_intrel      DB 'Error when restoring interrupts.',0
err_reload      DB 'ADFDebug already loaded.',0
err_notload     DB 'ADFDebug not loaded.',0

txt_loaded      DB 13,10,'ADFDebug loaded.',13,10,0
txt_timeload    DB 13,10,'ADFDebug loaded with time measurement.',13,10,0
txt_unload      DB 13,10,'ADFDebug unloaded.',13,10,0
txt_deb_none    DB 13,10,'Debug output: None',13,10,0
txt_deb_screen  DB 13,10,'Debug output: Screen',13,10,0
txt_deb_file    DB 13,10,'Debug output: File',13,10,0

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

ascstr:         lodsb
                cmp al,32
                jbe ascstr1
                stosb
                loop ascstr
                stc
                ret

ascstr1:        dec si
                xor al,al
                stosb
                ret

                ALIGN 2

asc8dec:        xor al,al
                mov bl,10
asc8dec1:       mov cl,[si]
                sub cl,'0'
                jc asc8dec3
                cmp cl,bl
                jae asc8dec3
                inc si
                mul bl
                and ah,ah
                jnz asc8dec2
                add al,cl
                jnc asc8dec1
asc8dec2:       stc
                ret
asc8dec3:       cmp BYTE PTR [si],33
                cmc
                ret

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

                mov si,OFFSET txt_doc_init
                call print

main2:          mov     ah,30H
                int     21H
                cmp     al,3
                jb      main3
                ja      main4
                cmp     ah,1
                jae     main4
main3:          mov     si,OFFSET err_dosver
                jmp     short print_quit_err

main4:          call    block_init
                jnc     main5

main4a:         mov     si,OFFSET err_tsr
                jmp     short print_quit_err

main5:          mov ax,cs
                mov es,ax
                mov bx,[pspseg]
                sub ax,bx
                cmp ax,10H
                jnz main4a
                mov si,OFFSET arg_buf+1
                call jmp_white
                jnc parse1

                mov si,OFFSET txt_doc_usage
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

parse1:         lodsb
                cmp BYTE PTR [si],33
                jnc arg_err
                and al,11011111B        ;Lower to upper case for 'a' to 'z'
                cmp al,'L'
                jz cmd_load
                cmp al,'U'
                jz to_cmd_unload
                cmp al,'N'
                jz cmd_none
                cmp al,'S'
                jz cmd_screen
                cmp al,'F'
                jz cmd_file
                jmp arg_err

to_cmd_unload:  jmp cmd_unload

cmd_load:       call jmp_white
                lodsb
                jc cmd_load_end
                cmp al,'/'
                jz cmd_load1
                cmp al,'-'
                jnz arg_err
cmd_load1:      lodsb
                and al,11011111B        ;Lower to upper case for 'a' to 'z'
                cmp al,'T'
                jnz cmd_load2
                mov [debug_timer],1
                jmp cmd_load
cmd_load2:      cmp al,'S'
                jnz arg_err
                call asc8dec
                jc arg_err
                mov [debug_sep],al
                jmp cmd_load

cmd_load_end:   jmp tsrload

cmd_none:       call jmp_white
                jnc to_arg_err
                call find_tsr
                jz not_loaded
                add dx,8
                mov ds,dx
                mov [debug_mode],0
                mov si,OFFSET txt_deb_none
                jmp print_exit_ok

cmd_screen:     call jmp_white
                jnc to_arg_err
                call find_tsr
                jz not_loaded
                add dx,8
                mov ds,dx
                mov [debug_mode],1
                mov si,OFFSET txt_deb_screen
                jmp print_exit_ok

to_arg_err:     jmp arg_err

cmd_file:       call jmp_white
                jc to_arg_err
                mov di,OFFSET DebFileName
                mov cx,32
                call ascstr
                jc to_arg_err
                call jmp_white
                jnc to_arg_err
                call find_tsr
                jz not_loaded
                mov di,OFFSET DebFileName
                mov si,di
                mov cx,16       ;32/2
                add dx,8
                mov es,dx
                cli
                mov es:[debug_mode],2
                rep movsw
                sti
                mov si,OFFSET txt_deb_file
                jmp print_exit_ok

not_loaded:     mov si,OFFSET err_notload
                jmp print_quit_err

cmd_unload:     call jmp_white
                jnc to_arg_err
                call find_tsr
                jz not_loaded
                push dx
                add dx,8
                mov ds,dx
                mov es,dx
                xor al,al
                xchg al,[debug_timer]
                and al,al
                jz cmd_unload1
                mov bx,OFFSET sysint08us
                call int_term
                jc intrel_err
cmd_unload1:    mov bx,OFFSET fossil
                call int_term
                jc intrel_err
                pop dx
                mov es,dx
                mov ah,49H
                int 21H
                jc free_err
                mov si,OFFSET txt_unload
                jmp print_exit_ok

intrel_err:     mov si,OFFSET err_intrel
                jmp print_quit_err

reload_err:     mov si,OFFSET err_reload
                jmp print_quit_err

free_err:       mov si,OFFSET err_free
                jmp print_quit_err

tsrload:        call find_tsr
                jnz reload_err

                mov es,[pspseg]
                mov es,es:[2CH]
                mov ah,49H
                int 21H
                jc free_err

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

                mov si,OFFSET txt_loaded
                cmp [debug_timer],0
                jz tsrload2

                mov bx,OFFSET sysint08us
                call int_init
tsrload1:       sti
                cmp [ustimer],0
                jz tsrload1
                mov si,OFFSET txt_timeload

tsrload2:       mov bx,OFFSET fossil
                call int_init

                mov ax,cs
                mov ds,ax
                mov es,ax
                call print

                test [exit_flags],00000001B
                jz tsrload3
                and [exit_flags],11111110B
                mov bx,[old_umb]
                mov ax,5803H
                int 21H
tsrload3:       mov ax,OFFSET tsr_end + 15+128  ;Include PSP
                mov cl,4
                shr ax,cl
                cmp ax,10H
                jnc tsrload4
                mov ax,10H
tsrload4:       mov dx,ax
                mov ax,3100H
                int 21H
                jmp prg_quit

PROG            ENDS

DATA            SEGMENT PARA PUBLIC 'DATA'

arg_buf         DB 128 DUP(?)

DATA            ENDS

STACK           SEGMENT PARA STACK 'STACK'

                DB 2048 DUP(?)

STACK           ENDS

                END main
