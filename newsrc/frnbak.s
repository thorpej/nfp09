;
; TTL 'FRONT AND BACK END - COPYRIGHT (C) MOTOROLA 1980.'
; NAM FRNBAK
;
; COPYRIGHT (C) MOTOROLA 1980.
;
;*****************************************************************
;
; F R N B A K
;
;  FRONT AND BACK END PROCESSOR. THIS BLOCK OF CODE CONTAINS ALL
;  THE FRONT AND BACK END PROCESSING FOR ALL THE FUNCTIONS.
;  IT INITIALIZES THE STACK FRAME, LOADS THE ARGUMENTS,
;  CALLS THE OPERATIONS, CHECKS FOR TRAPS, RETURNS THE RESULT
;  AND CLOSES THE STACK FRAME. FOR STACK CALLS, IT ALSO
;  MANIPULATES THE STACK.
;
;  TWO TYPES OF CALLS TO THE FP PACKAGE EXIST: STACK
;  CALLS AND REGISTER CALLS. EACH HAS A UNIQUE ENTRY
;  POINT.
;
;
;    LBSR  FPREG         REGISTER CALL
;    FCB   OPCODE
;
;        OR
;
;    LBSR FPSTAK         STACK CALL
;    FCB  OPCODE
;
;
;  MAJOR REVISIONS:
;
;      REVISER            DATE        REASON
;    JOEL BONEY          2-29-80      ORIGINAL
;    JOEL BONEY          4-21-80      SINGLE ENTRY POINTS
;    JOEL BONEY          7-02-80      REDUCE SIZE
;    JOEL BONEY          7-25-80      INCLUDE TPARAM IN IREG/ISTACK
;                                     CALLS
;    JOEL BONEY          7-29-80      INCLUDE HEADER AND COPYRIGHT
;    JOEL BONEY          8-20-80      IMPROVE PERFORMANCE
;    JOEL BONEY         12-08-80      UPDATE HEADER
;    @thorpej            6-25-22      Updated for asm6809.  New
;                                     comments are in mixed-case.
;
;****************************************************************
;
;  LINKING LOADER DEFINITIONS
;
;  XREF  IREG,GETARG,DISPAT,TRAP,MOVRSL,CLSTAK
;  XREF  ISTACK,SIZE,SIZTAB
;  XDEF  FPREG,FPSTAK
;  XDEF  ROMSTR
;****************************************************************
;
; Here is the label for the start of the ROM.
; NOTE: This label should always be the first
; byte in this module!
;
ROMSTR

;****************************************************************
;
; H E A D E R
;
;    THIS HEADER IS COMPATABLE WITH OS9-1 AND IS THOUGHT
;    TO CONTAIN SUFFICIENT INFORMATION TO BE USED IN
;    OTHER ROM-LINK SCHEMES.
;
; START OF STANDARD HEADER
	FDB	$87CD		; SYNC BYTES
	FDB	$2000		; MODULE SIZE (8K)
	FDB	MODNAME-ROMSTR	; OFFSET TO NAME
	FCB	$B1		; MULTI-MODULE,6809 OBJECT CODE
	FCB	$81		; SHAREABLE, REV. 1
;
; The OS9 documentation says:
;	The header check byte contains the one's complement of the
;	Exclusive-OR of the previous eight bytes.
;
	FCB	0		; XXXJRT fix me
; END OF STANDARD HEADER
; START OF MULTIMODULE INTERNAL ROUTINE DEFN'S
	if CONFIG_REG_ABI && CONFIG_STACK_ABI
	FCB	2		; 2 ENTRIES
	else
	FCB	1		; 1 ENTRY
	endif
	if CONFIG_REG_ABI
; ENTRY1	(symbol not referenced)
	FCC	"RE"		; NAME=REG
	FCB	$80+'G'
	FDB	FPREG-ROMSTR	; OFFSET TO ENTRY
	FDB	0		; AMOUNT OF PERM STORAGE
	FDB	155		; MAX STACK SIZE
	endif
	if CONFIG_STACK_ABI
; ENTRY2	(symbol not referenced)
	FCC	"STA"		; NAME=STAK
	FCB	$80+'K'
	FDB	FPSTAK-ROMSTR	; OFFSET TO ENTRY
	FDB	0		; PERMANENT STORAGE
	FDB	185		; MAX STSACK SIZE
	endif
; START OF MULTIMODULE EXTERNAL REFS
	FCB	0		; NO EXTERNAL REFS
;
;******** END OF OS9-1 TYPE HEADER ******************************
;
; MAIN MODULE NAME
MODNAME	FCC	"NFP09"
	if CONFIG_REG_ABI && CONFIG_STACK_ABI
	; nothing
	elsif CONFIG_REG_ABI
	FCC	"-REG"
	else
	FCC	"-STACK"
	endif
	FCC	"-V"
	FCB	$80+NFP09_VERSION
;
; KEEP THE COURTS HAPPY; PUT A COPYRIGHT MESSAGE IN
; HUMAN READABLE MACHINE FORM.
;
	FCC	"COPYRIGHT (C) MOTOROLA 1980"
;
; MAIN JUMP TABLE
;
	if CONFIG_REG_ABI
FPREG	BRA	REGST		; GO TO REGISTER CALL
	endif
	if CONFIG_STACK_ABI
FPSTAK	BRA	STKST		; GO TO STACK CALL
	endif
;
;******** END OF ALL HEADER INFO ********************************
;
;****************************************************************
;
;  ENTRY POINTS FOR FUNCTIONS
;
;  ALL CALLS TO THE FP PACKAGE COME THRU THIS FUNCTION
;  SELECT ROUTINE. TWO TYPES OF CALLS EXIST: STACK
;  CALLS AND REGISTER CALLS.
;

	if CONFIG_REG_ABI
;****************************************************************
;
;  REGISTER CALL ENTRY POINT
;
;  FORM OF CALL:
;     LBSR FPREG
;     FCB  OPCODE
;
REGST				; FPREG JUMPS TO HERE
	PSHS_ALL		; PUSH CALLER'S REGS
	LEAX	REGJT,PCR	; GET PTR TO REGISTER JUMP TABLE
	BRA	1F		; JOIN MUTUAL ENTRY
	endif	; CONFIG_REG_ABI

	if CONFIG_STACK_ABI
;****************************************************************
;
;  STACK CALL ENTRY POINT
;
;  FORM OF CALL:
;    LBSR FPSTAK
;    FCB  OPCODE
;
STKST				; FPSTAK JUMPS TO HERE
	PSHS_ALL		; PUSH CALLER'S REGS
	LEAX	STAKJT,PCR	; GET PTR TO STACK ENTRY JUMP TABLE
	endif

;
;  MUTUAL ENTRY CODE. X CONTAINS THE ADDRESS OF THE
;  JUMP TABLE TO USE AND U CONTAINS A PTR TO THE
;  PROPER STACK FRAME INIT ROUTINE
;
;  ON THE JUMP TO THE FUNCTION,  Y CONTAINS A PTR TO
;  THE ADDRESS JUST ABOVE THE ^FPCB ON THE STACK IFF
;  THE CALL IS A STACK CALL. THRU OUT THE DOCMENTATION
;  THIS POINTER IS REFERED TO AS '^TOS' OR 'PTOS'.
;
1	LDY	SIZREG,S	; GET PTR TO CALLER'S PC
	LDB	,Y		; GET OPCODE
	ANDB	#$3F		; ISOLATE OPCODE INDEX
	; IF B,GT,#FCMAX	IF OPCODE IS ILLEGAL
	;   LDB  #FCMAX+2	SUPPLY DUMMY OPCODE
	; ENDIF
	CMPB	#FCMAX
	BLE	1F
	LDB	#FCMAX+2
1
	LDD	B,X		; GET OFFSET FROM JUMP TABLE
	LEAX	D,X		; ADDR OF ROUTINE IS NOW IN X
	LDA	,Y+		; GET OPCODE AGAIN AND BUMP RETURN PC
	STY	SIZREG,S	; STORE RETURN PC
	LEAY	SIZREG+4,S	; GET ^TOS FOR STACK CALLS
	JMP	,X		; GO TO ROUTINE

	if CONFIG_REG_ABI
;
; REGISTER CALL JUMP TABLE
;   TABLE MUST CONTAIN RELATIVE ADDRESSES TO THE START
;   OF THE TABLE.
;
REGJT
	FDB	RDYAD-REGJT	; ADD
	FDB	RDYAD-REGJT	; SUB
	FDB	RDYAD-REGJT	; MUL
	FDB	RDYAD-REGJT	; DIV
	FDB	RDYAD-REGJT	; REM
	FDB	RFPCMP-REGJT	; COMPARE
	FDB	RFPCMP-REGJT	; TRAPPING COMPARE
	FDB	RFPPCM-REGJT	; PREDICATE COMPARE
	FDB	RFPPCM-REGJT	; TRAPPING PREDICATE COMPARE
	FDB	MONAD-REGJT	; SQRT
	FDB	MONAD-REGJT	; INTEGER PART
	FDB	RFPFXS-REGJT	; FIXS
	FDB	RFPFXD-REGJT	; FIXD
	FDB	RFPMOV-REGJT	; MOVE
	FDB	RFPBD-REGJT	; BINDEC
	FDB	MONAD-REGJT	; AB
	FDB	MONAD-REGJT	; NEG
	FDB	RFPDB-REGJT	; DECBIN
	FDB	RFPFLS-REGJT	; FLTS
	FDB	RFPFLD-REGJT	; FLTD
	FDB	RBADCAL-REGJT	; BAD CALL EXIT
	endif	; CONFIG_REG_ABI

	if CONFIG_STACK_ABI
;
; STACK CALL JUMP TABLE
;   TABLE MUST CONTAIN RELATIVE ADDRESSES TO THE START
;   OF THE TABLE.
;
STAKJT
	FDB	SDYAD-STAKJT	; ADD
	FDB	SDYAD-STAKJT	; SUB
	FDB	SDYAD-STAKJT	; MUL
	FDB	SDYAD-STAKJT	; DIV
	FDB	SDYAD-STAKJT	; REM
	FDB	SFPCMP-STAKJT	; COMPARE
	FDB	SFPCMP-STAKJT	; TRAPPING COMPARE
	FDB	SFPCMP-STAKJT	; PREDICATE COMPARE
	FDB	SFPCMP-STAKJT	; TRAPPING PREDICATE COMPARE
	FDB	SMON-STAKJT	; SQRT
	FDB	SMON-STAKJT	; INTEGER PART
	FDB	SFPFXS-STAKJT	; FIXS
	FDB	SFPFXD-STAKJT	; FIXD
	FDB	SFPMOV-STAKJT	; MOVE
	FDB	SFPBD-STAKJT	; BINDEC
	FDB	SMON-STAKJT	; AB
	FDB	SMON-STAKJT	; NEG
	FDB	SFPDB-STAKJT	; DECBIN
	FDB	SFPFLS-STAKJT	; FLTS
	FDB	SFPFLD-STAKJT	; FLTD
	FDB	SBADCAL-STAKJT	; BAD CALL EXIT
	endif	; CONFIG_STACK_ABI

;
;****************************************************************
;
;    LOCAL MACROS
;
;****************************************************************
;

;
; UP
;
;  LOCAL MACRO TO MOVE THE RETURN PC UP THE STACK N BYTES,
;  RESTORE THE CALLER'S REGISTERS,FIX THE STACK POINTER
;  AND RETURN TO THE ORIGINAL CALLER. N MUST BE GE 2.
;
; THIS USED TO BE AN IN LINE MACRO EXPANSION, BUT IT WAS
; CONVERTED TO A BRANCH TO COMMON CODE FOR BYTE EFFICIENCY.
;
UP	macro
	LDB	#\1		; B CONTAINS N
	LBRA	DO_UP
	endm

;
;  COMMON EXIT PROCESSING WHEN A STACK SHOULD BE MOVED
;  UP N BYTES. THIS COMMON CODE IS ENTERED BY THE 'UP'
;  MACRO
;
;  B REGISTER CONTAINS 'N' ON ENTRY
;  S POINTS TO BOTTOM OF USER REGISTERS
;
DO_UP
	LEAY	SIZREG,S	; GET PTR TO PC ON STACK
	LEAU	B,Y		; GET PTR TO WHERE WE WANT TO MOVE PC TO
	; MOVD (,Y),(,U)	  MOVE PC UP STACK
	LDD	,Y
	STD	,U
	STU	,Y		; STORE NEW SP WHERE PC USED TO BE
	PULS_ALL		; RESTORE ALL REGS EXCEPT PC
	LDS	,S		; GET NEW SP (WHICH POINTS TO RETURN ADDRESS)
	RTS

;
; DOWN
;
;  LOCAL MACRO TO MOVE CALLER'S REGS DOWN THE STACK
;  N BYTES
;  CALCULATES THE PROPER ^TOS AND LEAVES IT IN THE Y REG.
;
DOWN	macro
	LDB	#\1
	LBSR	DWNSUB
	endm

;
; SUBROUTINE TO MOVE THE REGISTERS DOWN THE STACK 'B' BYTES.
;
; ON ENTRY B CONTAINS THE NUMBER OF BYTES TO MOVE DOWN
;
; ON EXIT ALL REGISTERS ARE RESTORED (INCLUDING Y)
;
DWNSUB
	NEGB			; MOVE SP DOWN B LOCATIONS
	LEAS	B,S
	PSHS	A,X,Y		; PUSH SOME REGS
	LEAX	5,S		; X NOW PTS TO DESTINATION
	NEGB			; MAKE B POSITIVE AGAIN
	ADDB	#5
	LEAY	B,S		; Y NOW PTS TO SOURCE
	LDB	#SIZREG+4	; MOVE ALL REGS AND BOTH PC'S
1
	; MOVA (,Y+),(,X+)	  MOVE 1 BYTE
	LDA	,Y+
	STA	,X+
	DECB
	BNE	1B
	PULS	A,X,Y,PC	; PULL REGS AND RETURN

	if CONFIG_REG_ABI
;****************************************************************
;
;
;   REGISTER CALLS
;
;
;  FOR MOST REGISTER CALLS THE INCOMMING REGISTERS LOOK LIKE:
;    U = ^ARG1
;    Y = ^ARG2
;    X = ^RESULT
;    D = ^FPCB
;
;  FOR MONADIC CALLS ARG2 IS THE SINGLE ARGUMENT, HENCE U IS
;  A DON'T CARE.
;
;  FOR MOVES THE REGISTERS ARE DEFINED AS:
;    U = PARAMETER WORD
;    Y = ^ARG2
;    X = ^RESULT
;    D = ^FPCB
;
;  FOR COMPARES THE REGISTERS ARE DEFINED AS:
;    U = ^ARG1
;    Y = ^ARG2
;    X = PARAMETER WORD
;    D = ^FPCB
;
;
;  FOR FLOAT TO BCD AND BCD TO FLOAT SEE THE ROUTINE
;  HEADER FOR ARGUMENT DETAILS.
;
;
;  BY THE TIME THE PROGRAM ACTUALLY GETS TO HERE THE REGISTERS
;  LISTED ABOVE ARE DESTROYED. HENCE, THE SUBROUTINES MUST
;  GET THE REGISTER VALUES FROM THE STACK FRAME WHERE THEY
;  ARE SAVED.
;
;  ON ENTRY THE U REGISTER CONTAINS THE ADDRESS OF 'ISTACK'.
;  THIS WAS DONE TO REDUCE THE SIZE OF THE NUMEROUS LBSR ISTACK'S.
;
;  ALL REGISTER ARE RESTORED ON EXIT.
;
;********* MONADIC CALLS ****************************************
;
;  INTEGER PART, SQUARE ROOT, ABSOLUTE VALUE, NEGATE AND
;  SOME MOVES.
;
MONAD
	LBSR	IREG		; INIT STACK FOR REG CALL
	BRA	RMON		; GO JOIN MUTUAL PROCESSING

;********* DYADIC CALLS *****************************************
;
;  REGISTER CALL
;
;  ADD SUB MUL DIV REM
;
;
;  THIS CODE IS USED BY THE FOLLOWING DYADIC REGISTER CALLS:
;       ADD, SUB, MUL, DIV, REM
;
RDYAD
	LBSR	IREG		; GO INIT STACK FRAME
	LDY	PARG1,U		; GETARG(PARG1,^ARG1)
	LEAX	ARG1,U
	CLRB			; ARGUMENT 1 FLAG
	LBSR	GETARG
	BCC	RDYXIT		; TRAPPING NAN ABORT
;
;  ENTER HERE FOR MONADIC CALLS:
;    SQRT, INT
;
RMON
	LDB	#1		; ARGUMENT 2 FLAG
	LDY	PARG2,U		; GETARG(PARG2,^ARG2)
	LEAX	ARG2,U
	LBSR	GETARG
;
; ENTER HERE FROM MOVE
;
IMOV
	BCC	RDYXIT		; TRAPPING NAN ABORT
;
; ENTER HERE FOR INTEGER TO FLOAT
; ENTER HERE FOR DECIMAL BCD TO FLOAT
;
IFLOAT
	LBSR	DISPAT		; GO DO FUNCTION
SKIPFN
	LBSR	TRAP		; TRAPS?
	; IFCC CS		  IF WE SHOULD RETURN RESULT THEN
	;   LDX  PRESUL,U	  MOVERESULT(PRESUL)
	;   LBSR MOVRSL
	; ENDIF
	BCC	RDYXIT
	LDX	PRESUL,U
	LBSR	MOVRSL
RDYXIT
	LBSR	CLSTAK		; CLOSE STACK
; BAD CALL ABORT.
;   HERE WHEN CALLING OPCODE WAS ILLEGAL. JUST EXIT
RBADCAL
	PULS_ALLPC

;
; GET1 - GETARG1(PARG1,^ARG1)
;
; LOCAL SUBROUTINE FOR REGISTER CALLS.
; ON EXIT C IS SET IF TRAPPING NAN
;
GET1
	LDY	PARG1,U 	; GETARG(PARG1,^ARG1)
	LEAX	ARG1,U
	CLRB			; ARGUMENT 1 FLAG
	BRA	GT2OUT		; GO EXIT

;
; GET2 - GETARG2(PARG2,^ARG2) FOR MOST FUNCTIONS
; GET2M - GETARG2(SOURCE,^ARG2) FOR MOVES ONLY
;
; LOCAL SUBROUTINE FOR REGISTER CALLS.
; ON EXIT C IS SET IF TRAPPING NAN
;
GET2
	LDB	#1		; ARGUMENT 2 FLAG (USUALLY)
; ENTER HERE TO GET ARG2 (SOURCE) FOR MOVES
GET2M
	LDY	PARG2,U		; GETARG(PARG2,^ARG2)
	LEAX	ARG2,U
GT2OUT
	LBSR	GETARG
	RTS

;********* NON PREDICATE COMPARES *******************************
;
;  REGISTER CALL
;
;  FOR COMPARES THE REGISTERS ARE DEFINED AS:
;    U = ^ARG1
;    Y = ^ARG2
;    X = PARAMETER WORD
;    D = ^FPCB
;
RFPCMP
	CLRB			; B = 0 = NO PREDICATE
	BRA	PCMPMT		; GO JOIN MUTUAL REGISTER COMPARE

;********* PREDICATE COMPARES ***********************************
;
;  REGISTER CALL
;
RFPPCM
	LDB	#1		; B = 1 = PREDICATE FLAG
;
;  MUTUAL PROCESSING FOR ALL REGISTER CALL COMPARES
;     B = 1 = IFF PREDICATE COMPARE; ELSE B = 0
;
PCMPMT
	LDX	XREG-CCREG,S	; GET PARAMETER WORD
	LBSR	IREG		; GO INIT STACK FRAME
	PSHS	B		; SAVE PREDICATE COMPARE FLAG
	BSR	GET1		; GETARG(PARG1,^ARG1)
	BCC	PCMXIT		; TRAPPING NAN ABORT
	BSR	GET2		; GETARG(PARG2,^ARG2)
	BCC	PCMXIT		; TRAPPING NAN ABORT
	LBSR	DISPAT		; GO DO FUNCTION
	LBSR	TRAP		; TRAPS?
	; IFCC  CS		  IF WE SHOULD RETURN RESULT THEN
	;   IFTST  (,S),NE,#0       IF PREDICATE COMPARE
	;     IFTST  (FRACTR,U),EQ,#0  IF PREDICATE IS TRUE THEN
	;       BSETA  Z,(CCREG,U)       SET Z BIT
	;     ELSE
	;       BCLRA  NZ,(CCREG,U)      CLEAR Z BIT
	;     ENDIF
	;   ENDIF
	; ENDIF
	BCC	PCMXIT		; IFCC CS
	TST	,S		;   IFTST (,S),NE,#0
	BEQ	PCMXIT
	TST	FRACTR,U	;     IFTST  (FRACTR,U),EQ,#0
	BNE	1F
	; BSETA  Z,(CCREG,U)
	LDA	CCREG,U
	ORA	#Z
	STA	CCREG,U
	BRA	PCMXIT
1
	; BCLRA  NZ,(CCREG,U)
	LDA	CCREG,U
	ANDA	#NZ
	STA	CCREG,U
PCMXIT
	BRA	RDYXIT		; CLOSE STACK AND EXIT

;********* FLOAT TO 32 BIT INTEGER ******************************
;
; RFPFXD
;
; REGISTER CALL
;
RFPFXD
	LDB	#1		; B = 1 = 32 BIT RESULT
	BRA	FXSCOM

;********* FLOAT TO 16 BIT INTEGER ******************************
;
; RFPFXS
;
; REGISTER CALL
;
RFPFXS
	CLRB			; B = 0 = 16 BIT RESULT
;
;  COMMON CODE FOR REGISTER 'FIXES'
;   A = FUNCTION CODE
;   B = 0 = 16 BIT RESULT
;   B NE 0 = 32 BIT RESULT
;
FXSCOM
	LBSR	IREG		; GO INIT STACK FRAME
	PSHS	B		; SAVE RESULT SIZE FLAG
	BSR	GET2		; GETARG(PARG2,^ARG2)
	BCC	FXSXIT		; TRAPPING NAN AORT
	LBSR	DISPAT		; GO DO 'FIX'
	LBSR	TRAP		; TRAPS
	; IFCC CS		  IF WE SHOULD RETURN RESULT THEN
	;   LDX  PRESUL,U
	;   MOVD  (FRACTR,U),(,X) MOVE 16 BITS OF RESULT
	;   IFTST  (,S),NE,#0     IF 32 BIT RESULT
	;     MOVD (FRACTR+2,U),(2,X)  MOVE LS BYTES OF RESULT
	;   ENDIF
	; ENDIF
	BCC	FXSXIT		; IFCC CS
	LDX	PRESUL,U
	; MOVD  (FRACTR,U),(,X)
	LDD	FRACTR,U
	STD	,X
	TST	,S		; IFTST  (,S),NE,#0
	BEQ	FXSXIT
	; MOVD (FRACTR+2,U),(2,X)
	LDD	FRACTR+2,U
	STD	2,X
FXSXIT
	BRA	RDYXIT

;********* 32 BIT INTEGER TO FLOAT ******************************
;
; RFPFLD
;
; REGISTER CALL
;
RFPFLD
	LBSR	IREG		; INIT STACK FOR REGISTER CALLS
	LDY	YREG,U		; GET PTR TO INTEGER
	; MOVD  (,Y),(FRACT2,U)   MOVE INTEGER TO ARG2
	LDD	,Y
	STD	FRACT2,U
	; MOVD  (2,Y),(FRACT2+2,U)
	LDD	2,Y
	STD	FRACT2+2,U
	; IFCC  EQ		  IF LS BYTES EQUAL
	;   LDD  ,Y		  SEE IF MS BYTES ARE TOO (SET Z BIT ACCORD'LY)
	; ENDIF
	BNE	1F
	LDD	,Y
1
	BRA	FLSCOM		; GO JOIN MUTUAL PROCESSING

;********* 16 BIT INTEGER TO FLOAT ******************************
;
; RFPFLS
;
; REGISTER CALL
;
RFPFLS
	LBSR	IREG		; INIT STACK FRAME FOR REGISTER CALL
	LDY	YREG,U		; GET PTR TO INTEGER
	; MOVD  (,Y),(FRACT2,U)	  MOVE 16 BIT INTEGER TO ARG2
	LDD	,Y
	STD	FRACT2,U
;
; COMMON ENTRY FOR 16,32 BIT INTEGER TO FLOAT STACK CALLS
;   ON ENTRY Z = 1 IFF INTEGER IS ZERO
;
FLSCOM
	; IFCC  EQ		  IF ZERO THEN
	;   MOVA #TYZERO,(TYPE2,U)  TYPE := ZERO
	; ENDIF
	BNE	1F
	LDA	#TYZERO
	STA	TYPE2,U
1
	LBRA	IFLOAT		; GO JOIN MUTUAL PROCESSING

;********* MOVE ARG2 TO RESULT **********************************
;
; RFPMOV
;
;  U = PARAMETER WORD
;  Y = ^ARG2
;  X = ^RESULT
;  D = ^FPCB
;
;  REGISTER CALL
;
;  IF THE PRECISION OF THE SOURCE = THE PRECISION OF
;  THE DESTINATION, THEN DON'T BUILD THE STACK FRAME
;  OR CALL THE DISPATCH ROUTINE. HANDLE THE WHOLE
;  CALL HERE.
;
RFPMOV
	LDD	UREG-CCREG,S	; RESTORE PARAMETER WORD
	LBSR	SIZEQ		; COMPARE PREC(ARG2) WITH PREC(RESULT)
	;
	; Pseudo-code for original IFCC-ELSE-ENDIF block; go read
	; the original for further details:
	;
	; IF Z is set
	;   Do move directly and return
	; ELSE
	;   Construct function parameter and branch to IMOV
	; ENDIF
	;
	BNE	1F
	; A CONTAINS INDEX (0-4)
	LDX	XREG-CCREG,S	; RESTORE PTR TO RESULT
	LDY	YREG-CCREG,S	; RESTORE PTR TO SOURCE
	CMPA	#2		; IF A,GE,#2
	BLT	2F		; No...
	LDB	8,Y		; Yes, extended precision
	STB	8,X
	LDB	9,Y
	STB	9,X
2
	CMPA	#1		; IF A,GE,#1
	BLT	2F		; No...
	; MOVD  (6,Y),(6,X)	  Yes, double (or extended) precision
	LDD	6,Y
	STD	6,X
	; MOVD  (4,Y),(4,X)
	LDD	4,Y
	STD	4,X
2
	; MOVD  (2,Y),(2,X)
	LDD	2,Y
	STD	2,X
	; MOVD  (,Y),(,X)
	LDD	,Y
	STD	,X
	PULS_ALLPC		; EXIT
1
	LDA	#FCMOV		; SET FUNCTION CODE
	LDX	UREG-CCREG,S	; X = PARAMETER WORD
	LBSR	IREG		; GO INIT STACK FRAME
	CLRB			; SET TO GET SOURCE (ARG2)
	LBSR	GET2M		; GET SOURCE
	LBRA	IMOV		; GO JOIN MUTUAL PROC.

;********* CONVERT DECIMAL BCD STRING TO FLOATING ***************
;
; RFPDB
;
; REGISTER CALL
;
; ON ENTRY:
;   X = ^RESULT
;   D = ^FPCB
;   U = PTR TO INPUT BCD STRING
;
RFPDB
	LBSR	IREG		; GO INIT STACK FRAME
	LDX	UREG,U		; GET PTR TO INPUT STRING
	LDB	POFF,X		; GET P FROM STRING
	STB	P,U		; PUT IN TPARAM
	; MOVY (UREG,U),(FRACT2,U)   DECBIN ONLY GETS PTR TO STRING IN ARG2
	LDY	UREG,U
	STY	FRACT2,U
	LBRA	IFLOAT		; GO DO IT

;********* CONVERT FLOATING TO BCD STRING ***********************
;
;  RFPBD
;
;  REGISTER CALL
;
;  ON ENTRY:
;     U = K
;     X = ^ TO OUTPUT BCD STRING
;     Y = ^ARG2 (FLOATING)
;     D = ^FPCB
;
RFPBD
	LBSR	IREG		; INIT STACK FRAME
	; MOVD  (UREG,U),(TPARAM,U)  STORE K IN STACK FRAME
	LDD	UREG,U
	STD	TPARAM,U
	; MOVX  (XREG,U),(FRACTR,U)  STORE ^ARG2 IN RESULT FRACTION
	LDX	XREG,U
	STX	FRACTR,U
	LBSR	GET2		; GET ARG2
	BCC	RBDXIT		; TRAPPING NAN
	LBSR	DISPAT		; GO TO BINDEC
	LBSR	TRAP		; CHECK FOR TRAPS (RESULT ALREADY RETURNED)
RBDXIT
	LBRA	RDYXIT
	endif	; CONFIG_REG_ABI

	if CONFIG_STACK_ABI
;****************************************************************
;
;   STACK CALLS
;
;   FOR MOST STACK CALLS THE FOLLOWING ARGUMENTS ARE ON THE
;   STACK BEFORE THE CALL. FOR MONADIC CALLS ARG1 IS OMMITED
;
;     HIGH MEMORY   ARG1
;          |        ARG2               <-- PTOS,U
;     LOW MEMORY    POINTER TO FPCB
;
;   FOR COMPARES OR MOVES THE STACK ALSO CONTAINS THE PARAMETER WORD
;
;     HIGH MEMORY   ARG1
;          |        ARG2
;          |        TPARAM             <-- PTOS,U
;     LOW MEMORY    POINTER TO FPCB
;
;   ON RETURN FROM ALL STACK CALLS, ALL OF THE ABOVE
;   ARGUMENTS ARE REMOVED FROM THE STACK AND ONLY THE
;   RESULT IS ON THE STACK
;
;
;   FOR ALL STACK CALLS THE POINTER TO THE TOS (PTOS,U)
;   POINTS TO THE ADDRESS JUST ABOVE THE POINTER TO THE
;   FPCB DURING THE OPERATIONS. PTOS,U IS INITIALIZED BY ISTACK.
;
;
;  ON ENTRY TO THE FOLLOWING CODE Y POINTS TO THE LOCATION
;  JUST ABOVE THE ^FPCB. THIS IS ^TOS (PTOS).
;  U CONTAINS THE ADDRESS OF 'ISTACK'. THIS WAS DONE TO REDUCE
;  THE SIZE OF THE NUMEROUS CALLS TO ISTACK.
;
;********* DYADIC CALLS *****************************************
;
; COMMON ENTRY FOR STACK CALLS TO:
;   ADD,SUB,MUL,DIV AND REM
;
SDYAD
	LBSR	ISTACK
	; Y STILL POINTS TO TOS
	LEAX	ARG2,U		; GETARG(^TOS,^ARG2)
	LBSR	GETARG
	BCC	SDYXIT		; EXIT IF TRAPING NAN ABORT
	BSR	RSIZE		; TEMP:=^TOS+SIZE(ARG2)
	PSHS	A		; PUSH RESULT SIZE
	LEAY	A,Y
	LEAX	ARG1,U		; GETARG(TEMP,^ARG1)
	LBSR	GETARG
	BCC	SDYXIT		; EXIT IF TRAPPING NAN ABORT
	PSHS	Y		; SAVE TEMP (PTR TO RESULT)
	LBSR	DISPAT		; GO DO FUNCTION
	LBSR	TRAP		; TRAPS?
	PULS	X		; X:=TEMP
	; IFCC CS		  IF RESULT SHOULD BE RETURNED THEN
	;   LBSR  MOVRSL	  MOVERESULT(TEMP)
	; ENDIF
	BCC	SDYXIT
	LBSR	MOVRSL
SDYXIT
	LDB	,S		; GET RESULT SIZE
	ADDB	#2
	LBSR	CLSTAK		; CLOSE STACK
	LBRA	DO_UP		; MOVE STACK UP RESULT SIZE + 2 AND EXIT

;
; RSIZE
;
; LOCAL SUBROUTINE TO CALCULATE THE SIZE OF THE
;  RESULT. ASSUMES RPREC IS ALREADY STORED ON
;  THE STACK FRAME
;  (CALCULATES SIZE OF ARG2 FOR COMPARES AND THE
;   DESTINATION FOR MOVS.)
;
;  ON EXIT A CONTAINS THE SIZE OF RESULT
;
RSIZE
	PSHS	Y
	LDA	RPREC,U		; GET PRECISION OF RESULT
	LSRA			; DIVIDE INDEX BY 2
	LEAY	SIZTAB,PCR	; PTR TO CONVERSION TABLE
	LDA	A,Y		; GET SIZE
	PULS	Y,PC		; RESTORE AND RETURN

;********* MONADIC CALLS ****************************************
;
;  STACK CALL
;
;  SQUARE ROOT , INTEGER PART, ABSOLUTE VALUE, NEGATE
;
;
;  COMMON ENTRY FOR STACK CALLS TO MONADIC OPERATIONS:
;     SQRT, INT
;
SMON
	LBSR	ISTACK
	; Y STILL CONTAINS ^TOS
	LEAX	ARG2,U		; GETARG(^TOS,^ARG2)
	LBSR	GETARG
	BCC	SMONX		; EXIT IF TRAPPING NAN ABORT
	LBSR	DISPAT		; GO DO FUNCTION
	LBSR	TRAP		; TRAPS?
	; IFCC CS		  IF WE SHOULD RETURN RESULT THEN
	;   LDX  PTOS,U		  MOVERESULT(^TOS)
	;   LBSR  MOVRSL
	; ENDIF
	BCC	SMONX
	LDX	PTOS,U
	LBSR	MOVRSL
SMONX
	LBSR	CLSTAK		; CLOSE STACK
	UP 2			; MOVE REGS UP BY 2 AND EXIT

;********* MONADIC CALLS ****************************************
;
;  SFPCMP
;
;
;  ON ENTRY:
;     S POINTS TO PARAMETER WORD
;   2,S POINTS TO POINTER TO FPCB
;   4,S POINTS TO ARG2 ON USERS STACK
;
;  SOME LOCAL EQUATES FOR ALL COMPARES:
;    SINCE STACK COMPARES BUILD SOME TEMPORARY AREA
;    BETWEEN THE CALLER'S DATA ON THE STACK AND THE
;    STACK FRAME, THERE ARE SOME ADDITIONAL OFFSETS
;    FROM THE STACK FRAME POINTER
;
CFLAG	EQU	CALLPC+2	; 1 = PREDICATE CALL
CSP	EQU	CFLAG+1		; STACK POINTER JUST BEFORE FINAL RTS
CPARG1	EQU	CSP+2		; POINTER TO ARG1 IN USER STACK
CPARAM	EQU	CPARG1+2	; USER PARAMETER
CFPCB	EQU	CPARAM+2	; POINTER TO USER'S FPCB
CARG2	EQU	CFPCB+2		; OFFSET TO ARG2 IN USER STACK
TSIZE	EQU	CPARG1-CALLPC	; SIZE OF TEMPORARY AREA
;
;   MUTUAL PROCESSING FOR ALL STACK COMPARES
;
;  AFTER THE PC IS MOVED DOWN (SEE CODE BELOW) THE
;  STACK FRAME LOOKS LIKE:
;
;        ITEM      SIZE      OFFSET FROM U
;        ARG1       ?
;        ARG2       ?        CARG2
;        TPARAM     2        CPARAM
;        ^FPCB      2        CFPCB
;        ^ARG1      2        CPARG1
;        ^LAST SP   2        CSP
;        PRED. FLAG 1        CFLAG
;        CALLERS PC 2        CALLPC
;        REGS       X
;        STACK FRAME
;                        <------- U
;
SFPCMP
	DOWN	TSIZE		; MOVE REGS DOWN TSIZE BYTES
	LDX	SIZREG,S	; GET RETURN PC (PTS ONE PAST OPCODE)
	LDA	-1,X		; GET OPCODE
	LDX	SIZREG+TSIZE+4,S ; GET PARAMETER WORD
	LBSR	ISTACK		; INIT STACK
	CLR	CFLAG,U		; 0= NON PRED. CALL
	; IF    A,EQ,#FCPCMP	  IF PREDICATE CALL THEN
	;   INC  CFLAG,U	  1 = PRED. CALL
	; ELSE
	;   IF  A,EQ,#FCTPCM	  IF PRED. CALL THEN
	;     INC  CFLAG,U	  1 = PRED. CALL
	;   ENDIF
	; ENDIF
	CMPA	#FCPCMP
	BEQ	1F
	CMPA	#FCTPCM
	BNE	2F
1	INC	CFLAG,U		; A == #FCPCMP || #FCTPCM
2	; STACK NOW LOOKS LIKE ABOVE
	BSR	RSIZE		; TEMP := SIZE(ARG2)
	ADDA	#CARG2		; CALCULATE POINTER TO ARG1 ON USER'S STACK
	LEAX	A,U
	STX	CPARG1,U	; SAVE IT
	CLRB			; SIZE(ARG1)
	LBSR	SIZE
	SUBB	#3		; CALCULATE POINTER TO LAST SP
	LEAX	B,X		; NOTE THAT LAST SP+3 IS ADDRESS OF RESULT IF
				; ANY LAST SP+1 WILL HOLD FINAL CCREG
	; IFTST (CFLAG,U),NE,#0   NEED SPACE FOR RESULT?
	;   LEAX -1,X		  IF SO THEN MOVE LAST SP DOWN 1
	; ENDIF
	TST	CFLAG,U
	BEQ	1F
	LEAX	-1,X
1
	STX	CSP,U		; SAVE LAST SP
;
; TEMPORARY AREA OF STACK IS NOW SETUP
;
	LEAY	CARG2,U		; GETARG(ARG2,^ARG2)
	LEAX	ARG2,U
	LDB	#1
	LBSR	GETARG
	BCC	SCXIT		; TRAPPING NAN ABORT
	LDY	CPARG1,U	; GETARG(PARG1,^ARG1)
	LEAX	ARG1,U
	CLRB
	LBSR	GETARG
	BCC	SCXIT		; TRAPPING NAN ABORT
	LBSR	DISPAT		; GO DO COMPARE
	LBSR	TRAP		; TRAPS?
	; IFCC CS		  IF RESULT SHOULD BE RETURNED
	;   LDX CSP,U
	;   IFTST  (CFLAG,U),NE,#0 IF THERE IS A RESULT (PREDICATE COMPARE)
	;     MOVA (FRACTR,U),(3,X) STORE PREDICATE RESULT
	;   ENDIF
	; ENDIF
	BCC	SCXIT
	LDX	CSP,U
	;
	; AT THIS POINT X POINTS TO:
	;   3,X  RESULT IF ANY
	;   1,X  PLACE FOR RETURN PC
	;   0,X  PLACE FOR RETURN CCREG
	;
	TST	CFLAG,U
	BEQ	SCXIT
	; MOVA (FRACTR,U),(3,X)
	LDA	FRACTR,U
	STA	3,X
SCXIT
	; MOVA (CCREG,U),(,X)	  MOVE RETURN CCREG
	LDA	CCREG,U
	STA	,X
	; MOVD (CALLPC,U),(1,X)	  MOVE PC UP STACK
	LDD	CALLPC,U
	STD	1,X
	LBSR	CLSTAK		; CLOSE STACK
	PULS_ALL		; RESTORE CALLER'S REGS
	LDS	CSP-CALLPC,S	; GET LAST SP
	PULS	CC,PC		; LOAD CC'S AND RETURN

;********* FLOAT TO 16 BIT INTEGER ******************************
;
; SFPFXS
;
; STACK CALL
;
SFPFXS
	LBSR	ISTACK		; GO INIT STACK FRAME
	BSR	STKFIX		; DO COMMON STACK 'FIX' CODE
	; IFCC CS		  IF RESULT SHOULD BE RETURNED THEN
	;   MOVY  (FRACTR,U),(-2,X)
	; ENDIF
	BCC	FIXMUT
	LDY	FRACTR,U
	STY	-2,X
	BRA	FIXMUT

;********* FLOAT TO 32 BIT INTEGER ******************************
;
; SFPFXD
;
; STACK CALL
;
SFPFXD
	LBSR	ISTACK		; GO INIT STACK FRAME
	BSR	STKFIX		; DO COMMON STACK 'FIX' CODE
	; IFCC CS		  IF RESULT SHOULD BE RETURNED THEN
	;   MOVY  (FRACTR,U),(-4,X)
	;   MOVY  (FRACTR+2,U),(-2,X)
	; ENDIF
	BCC	1F
	LDY	FRACTR,U
	STY	-4,X
	LDY	FRACTR+2,U
	STY	-2,X
1
	SUBA	#2
FIXMUT
	TFR	A,B
	LBSR	CLSTAK		; CLOSE STACK
	LBRA	DO_UP

;
; STKFIX
;   LOCAL SUBROUTINE FOR STACK 'FIXES'
;
; ENTER:
;  A = FUNCTION CODE
;  U = POINTER TO STACK FRAME
;  Y = ^TOS
; EXIT:
;  X = POINTER TO ADDRESS ABOVE CALLER'S ARGUMENT
;  A = ARGUMENT SIZE
;  C = 1 IFF RESULT SHOULD BE RETURNED
;
STKFIX
	LEAX	ARG2,U		; GETARG(^TOS,^ARG2)
	LBSR	GETARG
	BCC	1F
	LBSR	DISPAT		; GO DO FIX
	LBSR	RSIZE		; GET SIZE OF FLOATING ARG
	LDX	PTOS,U		; X := ^TOS + SIZE(RESULT)
	LEAX	A,X
	LBSR	TRAP		; GO DO TRAP IF ANY
1	RTS

;********* 32 BIT INTEGER TO FLOAT ******************************
;
; SFPFLD
;
; STACK CALL
;
SFPFLD
	BSR	EPREC		; GET PRECISION OF RESULT
	; IF  A,NE,#PRSIN	  IF NOT SINGLE THEN
	;   IF A,EQ,#PRDBL	    IF DOUBLE
	;     DOWN 2		      MOVE REGS DOWN 2
	;   ELSE
	;     DOWN 4		       EXTENDED, MOVE REGS DOWN 4
	;   ENDIF
	; ENDIF
	CMPA	#PRSIN		; A == #PRSIN?
	BEQ	1F		; Yes, skip.
	CMPA	#PRDBL		; A == #PRDBL?
	BEQ	2F		; Yes, go handle it.
	DOWN	4		; No, it's extended; move regs down 4.
	BRA	1F
2
	DOWN	2		; Double; move regs down 2.
1
	LDA	#FCFLTD		; SET FUNCTION CODE
	LBSR	ISTACK		; GO INIT STACK FRAME
	; Y STILL POINTS TO TOS
	LDB	#4		; SET 32 BIT FLAG
	; MOVX (,Y),(FRACT2,U)
	LDX	,Y
	STX	FRACT2,U
	; MOVX (2,Y),(FRACT2+2,U)
	LDX	2,Y
	STX	FRACT2+2,U
	; IFCC  EQ		  IF LEAST SIGNIFICANT BYTES = ZERO THEN
	;   LDX ,Y		  SET CC BITS FROM MS BYTES
	; ENDIF
	BNE	1F
	LDX	,Y
1
	BRA	FLSMUT

;
; EPREC - LOCAL SUBROUTINE TO DETERMINE THE PRECISION OF THE
;         RESULT BEFORE THE STACK FRAME IS BUILT.
;
; ON ENTRY THE PTR TO THE FPCB SHOULD BE ON THE STACK
; JUST ABOVE THE RETURN PC (THE ORIGINAL ONE; NOT THE PC
; GENERATED BY THIS CALL).
;
; ON EXIT A CONTAINS THE INDEX LEFT JUSTIFIED
;
EPREC
	LDA	[SIZREG+4,S]	; GET FPCB CONTROL BYTE
	ANDA	#$E0		; MASK OFF INDEX
	RTS

;********* 16 BIT INTEGER TO FLOAT ******************************
;
; SFPFLS
;
; STACK CALL
;
SFPFLS
	BSR	EPREC		; GET EARLY PRECISION OF RESULT
	; IF A,NE,#PRSIN	  IF NOT SINGLE THEN
	;   IF A,EQ,#PRDBL	  IF DOUBLE
	;     DOWN 4		  MOVE REGS DOWN 4
	;   ELSE
	;     DOWN 6		  EXTENDED, MOVE REGS DOWN 6
	;   ENDIF
	; ENDIF
	CMPA	#PRSIN		; A == #PRSIN?
	BEQ	1F		; Yes, skip.
	CMPA	#PRDBL		; A == #PRDBL?
	BEQ	2F		; Yes, go handle it.
	DOWN	6		; No, it's extended; move regs down 4.
	BRA	1F
2
	DOWN	4		; Double; move regs down 2.
1
	LDA	#FCFLTS		; SET FUNCTION CODE
	LBSR	ISTACK		; GO INIT STACK FRAME FOR STACK CALL
	; Y STILL POINTS TO TOS
	LDB	#2		; 16 BIT INTEGER FLAG
	; MOVX  (,Y),(FRACT2,U)
	LDX	,Y
	STX	FRACT2,U
;
; MUTUAL PROCESSING FOR STACK 'FLOAT' ROUTINES
;   ON ENTRY:
;    Z = 1 IFF INTEGER EQUALS ZERO
;    B = 2 = 16 BIT INTEGER
;    B = 4 = 32 BIT INTEGER
;
FLSMUT
	PSHS	B		; SAVE FLAGS
	; IFCC  NE		  IF NOT ZERO
	;   CLR TYPE2,U		  TYPE := NORMALIZED
	; ELSE
	;   MOVA #TYZERO,(TYPE2,U) TYPE := ZERO
	; ENDIF
	; XXXJRT Up in FLSCOM, the "TYPE := NORMALIZED" is not performed.
	; It might be that IREG zeros the stack frame and ISTACK does not?
	BEQ	1F
	CLR	TYPE2,U
	BRA	2F
1
	LDA	#TYZERO
	STA	TYPE2,U
2
	LBSR	DISPAT		; GO DO FLOAT
	LBSR	TRAP		; GO CHECK FOR TRAPS
	BCC	1F		; Skip if we should not return result.
	LDX	PTOS,U		; GET ^TOS
	LDB	,S		; GET FLAG (FLAG=NBR OF BYTES IN INTEGER)
	LEAX	B,X		; X := TOS + INTEGER SIZE - SIZE(RESULT)
	LBSR	RSIZE
	NEGA
	LEAX	A,X
	LBSR	MOVRSL		; MOVERESULT(X)
1
	PULS	B		; RESTORE FLAG
	LDA	RPREC,U		; GET PRECISION
	LBSR	CLSTAK		; CLOSE STACK
	; IF D,EQ,#4		  IF 32 BIT INTEGER AND SINGLE PRECISION...
	;   UP 2
	; ENDIF
	CMPD	#4
	BNE	1F
	UP	2
1
	PULS_ALLPC

;********* MOVE (CONVERT) TOP OF STACK **************************
;
; SFPMOV
;
; STACK CALL
;
; ON ENTRY STACK CONTAINS:
;      ARG2
;      PARAMETER WORD    <-- PTOS,U
;      POINTER TO FPCB
;
SFPMOV
	LDD	,Y		; GET SIZE PARAMETER
	LBSR	SIZEQ		; COMPARE PREC(ARG2) TO PREC(RESULT)
	; IFCC  EQ		  IF PREC(ARG2) = PREC(RESULT)
	;   UP 4		  MOVE REGS UP BY 4 AND EXIT
	; ENDIF
	BNE	1F
	; THIS IS BASICALLY A NOP
	UP	4		; MOVE REGS UP BY 4 AND EXIT
1
	; Y STILL POINTS TO TOS
	LDD	,Y		; GET SIZE PARAMETER AGAIN
	LDA	#16		; SHIFT LEFT 4 BITS
	MUL			; A=PREC(ARG2); B=PREC(RESULT)*16
	; IFTST  A,EQ,#0	  IF ARG2 IS SINGLE THEN
	;   IF B,GE,#$20	  IF SINGLE TO EXTENDED THEN
	;     DOWN 2
	;   ENDIF
	; ENDIF
	TSTA
	BNE	1F
	CMPB	#$20
	BLT	1F
	DOWN	2
1
	LDA	#FCMOV		; SET FUNCTION CODE
	LDX	,Y		; X = PARAMETER WORD
	LBSR	ISTACK		; ISTACK(^TOS,FCMOV)
	LEAY	2,Y		; GETARG(^TOS+2,^ARG2)
	LEAX	ARG2,U
	CLRB			; FLAG TO INDICATE SOURCE ARG (ARG2)
	LBSR	GETARG
	BCC	SMOVXT		; EXIT IF TRAPPING NAN
	LBSR	DISPAT		; GO DO CONVERT
	; CALCULATE RESULT ADDR EVEN IF WE DON'T HAVE TO RETURN RESULT
	LDX	PTOS,U		; X := ^TOS+2 + SIZE(ARG2) - SIZE(RESULT)
	LEAX	2,X
	CLRB			; SIZE(ARG2)
	LBSR	SIZE
	LEAX	B,X
	LBSR	RSIZE		; SIZE(RESULT)
	NEGA			; -SIZE(RESULT)
	LEAX	A,X
	TFR	X,D		; PUT RESULT ADDRESS IN D TOO
	LBSR	TRAP		; CHECK FOR TRAPS
	BCC	SMOVXT		; Skip it we shold not return a result
	LBSR	MOVRSL		; MOVERESULT(X)
;
;  CALCULATE THE DISTANCE BETWEEN THE ADDRESS JUST ABOVE
;  THE RETURN PC AND THE BOTTOM OF THE ARGUMENT. THIS
;  IS THE DISTANCE THE STACK SHOULD BE MOVED UP.
;
;  (CALLPC + 2,U) IS THE ADDRESS JUST ABOVE THE PC
;  D CONTAINS THE ADDR OF THE RESULT
;
SMOVXT
	LBSR	CLSTAK		; CLOSE STACK
	LEAY	CALLPC+2,U	; GET ADDR JUST ABOVE RETURN PC.
	PSHS	Y
	SUBD	,S++		; CALCULATE DISTANCE TO MOVE REGS UP
	LBNE	DO_UP		; IF NEEDED, GO MOVE UP AND EXIT
; BAD CALL ABORT.
;   HERE WHEN CALLING OPCODE WAS ILLEGAL. JUST EXIT
SBADCAL
	PULS_ALLPC		; NO MOVE UP NEEDED, EXIT

;********* CONVERT DECIMAL BCD STRING TO FLOATING (INS) *********
;
; SFPDB
;
; STACK CALL
;
; ON ENTRY STACK LOOKS LIKE
;       ENTRY                   SIZE     POINTER
;       BCD STRING              26
;       ^FPCB                    2
;
SFPDB
	LBSR	ISTACK		; INIT STACK FRAME
	; MOVA  (POFF,Y),(P,U)	  STORE P IN STACK FRAME
	LDA	POFF,Y
	STA	P,U
	STY	FRACT2,U	; DECBIN ONLY GETS PTR TO BCD STRING
	LBSR	DISPAT		; GO DO DECBIN
	LBSR	RSIZE		; CALCULATE ADDR OF RESULT
	TFR	A,B
	NEGB			; TEMP := ^TOS +27 -SIZE(RESULT)
	SEX
	ADDD	PTOS,U
	ADDD	#26		; XXXJRT double-check against ^^^
	TFR	D,X		; TEMP IS NOW IN X
	LBSR	TRAP		; GO CHECK TRAPS
	BCC	SMOVXT		; Get out if no result should be returned.
	LBSR	MOVRSL		; MOVERESULT(TEMP)
	; D CONTAINS PTR TO RESULT
	BRA	SMOVXT		; GO MOVE REGS UP, ETC. AND EXIT

;********* FLOATING TO BCD STRING (OUTS) ************************
;
; SFPBD
;
; STACK CALL
;
; STACK BEFORE CALL
;      ARG2    (4,8 OR 10 BYTES)
;      K       1 BYTE
;      ^FPCB   2 BYTES
;
SFPBD
	LBSR	EPREC		; GET PRECISION OF ARG2
	; MAKE ROOM FOR RESULT
	; IF A,EQ,#PRSIN	  IF SINGLE THEN
	;   DOWN 19		  {26-7}
	; ELSE
	;   IF A,EQ,#PRDBL	  IF DOUBLE THEN
	;     DOWN 15		  {26-11}
	;   ELSE		  {EXTENDED}
	;     DOWN 13		  {26-13}
	;   ENDIF
	; ENDIF
	CMPA	#PRSIN		; A == #PRSIN?
	BNE	1F		; No... check for double
	DOWN	19		; {26-7}
	BRA	2F
1
	CMPA	#PRDBL		; A == #PRDBL?
	BNE	1F		; No... it's extended.
	DOWN	15		; {26-11}
	BRA	2F
1
	DOWN	13		; {26-13}
2
	LDA	#FCBNDC		; SET FUNCTION OPCODE
	LBSR	ISTACK		; INIT STACK FRAME
	; MOVA (,Y+),(K,U)	  MOVE K ONTO THE STACK FRAME.AND BUMP Y
	LDA	,Y+
	STA	K,U
	LEAX	CALLPC+2,U	; GET ADDR OF RESULT
	STX	FRACTR,U	; STORE ^ TO RESULT IN RESULT FRACTION
	; Y PTS TO ARG2
	LEAX	ARG2,U		; GETARG(^TOS+1,^ARG2)
	LBSR	GETARG
	BCC	1F		; TRAPPING NAN ABORT
	LBSR	DISPAT		; GO TO BINDEC
	LBSR	TRAP		; PROCESS TRAPS (RESULT ALREADY RETURNED)
1
	LBSR	CLSTAK		; CLOSE STACK
	PULS_ALLPC		; ADIOS
	endif	; CONFIG_STACK_ABI

;
; SIZEQ
;
; COMPARE PRECISIONS OF ARGUMENTS FOR MOV
; LOCAL SUBROUTINE FOR STACK AND REGISTER MOVES
;
; ON ENTRY: D CONTAINS THE PARAMETER WORD
; ON EXIT: Z = 1 IFF ARGUMENTS ARE SAME PRECISION
;          A CONTAINS PRECISION OF SOURCE (ARG2)
;          B IS DESTROYED
;
SIZEQ
	TFR	B,A		; COPY PRECISION BYTE INTO A TOO
	ANDA	#$F		; GET PRECISION OF RESULT
	PSHS	A		; PUSH IT
	LDA	#16		; MOVE PRECISION OF ARG2 TO A-REG
	MUL
	CMPA	,S+		; COMPARE PREC(ARG2) TO PREC(RESULT)
	RTS
