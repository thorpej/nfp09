;
; TTL  'GET AND PUT ARGUMENTS FROM USER MEMORY'
; NAM  GETPUT
;
;   G E T P U T
;
;       THIS SOURCE INCLUDES 2 CALLABLE SUBROUTINES
;       THAT AID THE FRONT AND BACKEND PROCESSORS
;       TO GET AND PUT ARGUMENTS FROM USER MEMORY TO
;       THE INTERNAL STACK FRAME
;         1. GETARG
;         2. MOVRSL
;
;   MAJOR REVISIONS:
;     REVISER    DATE     REASON
;   JOEL BONEY  021480   ORIGINAL
;   JOEL BONEY  070280   SIZE REDUCTION
;   JOEL BONEY  071080   MORE SIZE REDUCTION
;   JOEL BONEY  072080   FIXED MOVRSL TO RETURN DENRM. NBRS.
;   JOEL BONEY  072580   MOD IREG/ISTACK TO SAVE PARAMETER WD.
;   JOEL BONEY  081480   REMOVE BIAS FROM EXTENDED DENORMALIZED.
;   JOEL BONEY  081980   IMPROVE PERFORMANCE
;   JOEL BONEY  082680   MOVE CODE THAT COPIES TSTAT TO FPCB
;                        FROM 'CLSTAK' TO 'TRAP'.
;   JOEL BONEY  082680   DONAN CALLS IOPSET INSTEAD OF IOP
;   JOEL BONEY  082980   UPDATE TO DRAFT 6.0. RM AND RP NO LONGER
;                        FORCE NORMALIZE MODE.
;   GREG S      103080   ASSURE THAT THE MSBIT OF EXTENDED INF'S
;                        IS A DON'T CARE.
;   GREG S      121680   INSERT TEST SO EXT. NORMALIZED VALUES
;                        AT MIN. EXP. DON'T GET TYPED AS NOT NORM.
;   @thorpej   6-26-22   Updated for asm6809.  New
;                        comments are in mixed-case.
;
;   COPYRIGHT (C) 1980 BY MOTOROLA
;
;
;*****************************************************************
;
;  LINKING LOADER DEFINITIONS
;
;  XDEF  GETARG,MOVRSL,TRAP,IREG,ISTACK,CLSTAK
;  XREF  SNORM,LNORM,TFRACT,PREC,IOPSUB,IOPSET
;
;*****************************************************************
;
;   G E T A R G
;
;     GET AN ARGUMENT FROM USER MEMORY AND PUT IT IN THE
;     STACK FRAME. DO THE NECESSARY EXPANSION TO INTERNAL
;     FORMAT. IF A NAN OCCURS, CHECK FOR A TRAPPING NAN.
;     IF THE ARGUMENT IS DENORMALIZED, CHECK TO SEE IF
;     IT SHOULD BE NORMALIZED DURING THE EXPANSION.
;
; ON ENTRY:
;     X = POINTER TO LOCATION OF ARGUMENT ON STACK FRAME
;     Y = POINTER TO ARGUMENT IN USER MEMORY
;     U = POINTER TO STACK FRAME
;     FOR CMP B=0 FOR ARG1; B.NE.0 FOR ARG2
;     FOR MOV B=0 FOR ARG2; B.NE.0 FOR RESULT
;     FOR OTHER FUNCTION B= DON'T CARE
;
; ON EXIT:
;     ALL REGISTERS RESTORED EXCEPT CC BITS
;     C = 1 NO TRAPPING NAN OCCURED OR TRAP HANDLER WANTS
;           US TO PROCEED.
;     C = 0 TRAPPING NAN OCCURED AND THE TRAP HANDLER
;           WANTS TO ABORT
;
; NOTE:
;     SINCE GETARG IS CALLED BY NEARLY EVERY FUNCTION, AND
;     SINCE CONSIDERABLE TIME COULD BE SPENT EXPANDING THE
;     ARGUMENTS, GETARG IS WRITTEN TO BE AS FAST AS IS
;     REASONABLY POSSIBLE. CONSIDERABLE BYTE SAVINGS CAN
;     BE OBTAINED IF THE MODIFIER WISHES TO SACRIFICE SPEED.
;
;*****************************************************************
;
; THE MAIN PART OF GETARG DETERMINES THE PRECISION OF THE ARGUMENT
; AND THEN CALLS THE APPROPRIATE SUBROUTINE TO HANDLE
; THAT PRECISION OF ARGUMENT
;
; XXXJRT We could make this routine a teensy bit smaller and faster
; by putting the restore-and-return as a fall-through in the Single
; case and make the others back-branch to it.
;
GETARG
	PSHS	D		; SAVE IT
	; SINCE ALL PRECISIONS HANDLE THE SIGN THE SAME WAY,
	; DO IT ONCE HERE.
	LDA	,Y		; GET SIGN
	ANDA	#$80
	STA	SIGN,X		; STORE IN STACK FRAME
	LBSR	PREC		; GET PRECISION OF ARGUMENT
	BNE	1F		; Not single...
	BSR	GETSGL
	BRA	2F
1
	CMPB	#2		; Double?
	BNE	1F		; Not double...
	LBSR	GETDBL
	BRA	2F
1
	LBSR	GETEXT		; Must be extended.
2
	ORCC	#C		; NO TRAPPING NAN
	PULS	D,PC

;*****************************************************************
;
;  GETSGL - SUBPROCEDURE TO GETARG
;     GET A SINGLE PRECISION ARGUMENT FROM THE USER MEMORY AND
;     PUT IT ON THE STACK FRAME. DO THE EXPANSION TO INTERNAL
;     FORMAT. IF A NAN OCCURS CHECK FOR TRAPPING NAN. IF ARG
;     IS DENORMALIZED, CHECK TO SEE IF IT SHOULD BE NORMALIZED.
;
;  ON ENTRY: SAME AS GETARG EXCEPT B IS UNDEFINED
;  ON EXIT:  SAME AS GETARG EXCEPT D IS DESTROYED
;
;*****************************************************************
GETSGL
	LDD	2,Y		; GET 16 LSB'S OF FRACTION FROM USER MEMORY
	STD	FRACT+1,X	; STORE THEM ON STACK FRAME
	LDB	,Y		; GET SIGN + 7 BITS OF EXPONENT
	LDA	1,Y		; GET 1 BIT OF EXPONENT + 7 BITS OF FRACTION
	ROLA			; SHIFT OUT EXPONENT
	ROLB			; SHIFT IN EXPONENT BIT
	LSRA			; SHIFT BACK FRACTION
	ORA	#BIT7		; ADD EXPLICIT 1.0 BIT
	STA	FRACT,X		; STORE UPPER 8 BITS OF FRACTION
	CLRA
	SUBD	#SBIAS		; MAKE EXPONENT 2'S COMPLEMENT
	STD	EXP,X		; SAVE EXPONENT
	CMPD	#-127		; Is type zero or denormalized?
	BEQ	1F		; No...
	; {MUST BE INFINITY,NAN OR NORMALIZED}
	CMPD	#128		; Normalized?
	BEQ	2F		; Nope..
	RTS			; Yes, exit here for speed (Z=1).
2
	BSR	CLREXP		; RESET EXPLICIT 1.0 BIT IN FRACTION
	LDD	#$7FFF		; SET CORRECT EXPONENT
	STD	EXP,X
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BEQ	2F		; Not a NaN.
	BSR	DONAN		; GO DO NAN PROCESSING
	BRA	3F		; ...and done.
2	; {INFINITY}
	LDA	#TYINF		; TYPE := INFINITY
	STA	TYPE,X
	BRA	3F		; ...and done.

1	; {ZERO OR DENORMALIZED}
	BSR	CLREXP		; RESET EXPLICIT 1.0
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BEQ	1F		; Go handle zero.
	INC	EXP+1,X		; EXPONENT = -126
	LDA	#TYNNRM		; TYPE := NOT NORMALIZED
	STA	TYPE,X
	BSR	TSTNRM		; GO NORMALIZE IF REQUIRED
	BRA	3F
1	; {ZERO}
	LDD	#$8000		; SET CORRECT EXPONENT
	STD	EXP,X
	LDA	#TYZERO		; TYPE := ZERO
	STA	TYPE,X
3
	RTS

;
;  D O N A N
;
;  SUBROUTINE (OF SORTS) TO DO PROCESSING FOR A NAN
;
;  IF THE NAN IS NON-TRAPPING, THEN TAKE A NORMAL EXIT WITH
;     THE TYPE SET TO NAN.
;
;  IF THE NAN IS A TRAPPING NAN THEN DO THE TRAP AND
;     EXIT TO THE CALLER OF GETARG WITH THE C BIT
;     RETURNED BY THE TRAP HANDLER. I KNOW THIS IS
;     TERRIBLY UNSTRUCTURED BUT IT SAVES MANY BYTES
;     OF CODE AND IMPROVES AVERAGE PERFORMANCE A LOT.
;
DONAN
	LDA	#TYNAN		; TYPE := NAN
	STA	TYPE,X
	LDA	FRACT,X		; IF NAN IS TRAPPING NAN THEN
	ROLA			; TEST BIT 6 (TRAPPING NAN BIT)
	BMI	1F		; IF NOT TRAPPING NAN
	RTS			; THEN EXIT TO CALLER
1	; This is a trapping NaN.
	LDA	#5		; INVALID OPERATION = 5
	LBSR	IOPSET
	LBSR	TRAP		; GO TRAP IF ENABLED
	LEAS	4,S		; RETURN TO CALLER OF GETARG (WITH C)
	PULS	D,PC

;
; CLREXP - CLEAR EXPLICIT 1.0 IN FRACTION
;
CLREXP
	LSL	FRACT,X		; MOVE MSB INTO CARRY
	LSR	FRACT,X		; MOVE A ZERO BACK
	RTS

;
; TSTNRM
;   TEST A DENORMALIZED NUMBER TO SEE IF IT SHOULD BE
;   NORMALIZED (NRM SET IN FPCB).
;   IF SO DO THE NORMALIZATION AND SET TYPE
;   TO NORMALIZED.
;
;   DESTROYS A REG
;
TSTNRM
	LDA	[PFPCB,U]	; CHECK FOR NORMALIZE MODE
	BITA	#CTLNRM
	BEQ	1F		; #CTLNRM not set
	LBSR	SNORM
1	RTS

;*****************************************************************
;
; GETDBL - SUBPROCEDURE TO GETARG
;
;    GET A DOUBLE PRECISION ARGUMENT FROM THE USER MEMORY
;    AND PUT IT ON THE STACK FRAME. DO THE EXPANSION TO
;    THE INTERNAL FORM. IF A NAN OCCURS, CHECK FOR A
;    TRAPPING NAN. IF ARGUMENT IS DENORMALIZED, CHECK TO
;    SEE IF IT SHOULD BE NORMALIZED.
;
; ENTRY: SAME AS GETARG EXCEPT B IS UNDEFINED
; EXIT:  SAME AS GETARG EXCEPT D IS DESTROYED
;
;*****************************************************************
GETDBL
	; MOVE FRACTION FROM USER MEMORY TO STACK FRAME A BYTE
	; AT A TIME. DO THE NECESSARY SHIFTING ALONG THE WAY
	LDA	#6		; PUT LOOP CTR ON STACK
	PSHS	A,Y,U		; ALONG WITH SOME OTHER REGS
	LEAY	1,Y		; Y NOW POINTS TO USER FRACTION
	LEAU	FRACT,X		; U NOW POINTS TO STACK FRAME FRACT.
1
	LDD	,Y+		; GET 'LAST' BYTE - UPPER 3 BITS ARE
				; DON'T CARES
	LSLB			; SHIFT 3 BITS FROM NEXT
	ROLA			; INTO LAST
	LSLB
	ROLA
	LSLB
	ROLA
	STA	,U+		; STORE PARTIAL ANSWER IN STACK FRAME
	DEC	,S		; DEC LOOP CTR
	BNE	1B
	STB	,U		; STORE LAST 5 BITS
	PULS	A,Y,U
	LDA	FRACT,X		; SET EXPLICIT 1.0 IN FRACTION
	ORA	#BIT7
	STA	FRACT,X
	LDD	,Y		; GET SIGN PLUS EXPONENT
	SRD4
	ANDA	#$07
	SUBD	#DBIAS		; REMOVE BIAS - MAKE 2'S COMPLEMENT
	STD	EXP,X
	CMPD	#-1023		; Is type zero or denormalized?
	BEQ	1F		; No...
	; {MUST BE INFINITY,NAN OR NORMALIZED}
	CMPD	#1024		; Normalized?
	BEQ	2F		; Nope...
	RTS			; Yes, exit here for speed (Z=1).
2
	BSR	CLREXP		; RESET 1.0 BIT IN FRACTION
	LDD	#$7FFF		; GET CORRECT EXPONENT
	STD	EXP,X
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BEQ	2F		; Not a NaN.
	BSR	DONAN		; GO DO NAN PROCESSING
	BRA	3F		; ...and done.
2	; {INFINITY}
	LDA	#TYINF		; TYPE := INFINITY
	STA	TYPE,X
	BRA	3F		; ...and done.

1	; {ZERO OR DENORMALIZED}
	BSR	CLREXP		; RESET 1.0 BIT IN FRACTION
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BEQ	1F		; Go handle zero.
	INC	EXP+1,X		; EXPONENT = -1022
	LDA	#TYNNRM		; TYPE := NOT NORMALIZED
	STA	TYPE,X
	BSR	TSTNRM		; GO NORMALIZE IF REQUIRED
	BRA	3F
1	; {ZERO}
	LDD	#$8000		; GET CORRECT EXPONENT
	STD	EXP,X
	LDA	#TYZERO		; TYPE := ZERO
	STA	TYPE,X
3
	RTS

;*****************************************************************
;
;    GETEXT - SUBPROCEDURE TO GETARG
;
;      GET AN EXTENDED PRECISION ARGUMENT FROM USER MEMORY AND
;      PUT IT ON THE STACK FRAME. DO EXPANSION TO INTERNAL
;      FORMAT. IF A NAN OCCURS CHECK FOR A TRAPPING NAN.
;
;    ENTRY: SAME AS GETARG EXCEPT B IS UNDEFINED
;    EXIT:  SAME AS GETARG EXCEPT D IS DESTROYED
;
;*****************************************************************
GETEXT
	LDD	2,Y		; MOVE FRACTION ONTO STACK FRAME
	STD	FRACT,X
	LDD	4,Y
	STD	FRACT+2,X
	LDD	6,Y
	STD	FRACT+4,X
	LDD	8,Y
	STD	FRACT+6,X
	LDD	,Y		; GET SIGN AND EXPONENT
	ANDA	#$7F		; REMOVE SIGN BIT
	CMPD	#$4000		; Is type zero or denormalized?
	BNE	1F		; No...
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BNE	2F		; No...
	LDD	#$8000		; EXPONENT = #$8000
	STD	EXP,X
	LDA	#TYZERO		; TYPE := ZERO
	STA	TYPE,X
	BRA	3F		; ...and done
2	; {DENORMALIZED}
	LDD	#$C000		; EXPONENT = -16384
	STD	EXP,X
	TST	FRACT,X		; SEE IF FRACT IS NORMALIZED
	BMI	3F		; IF SO, EXIT WITH TYPE <- NORMALIZED
	LDA	#TYNNRM		; ELSE, TYPE := NOT NORMALIZED
	STA	TYPE,X
	LBSR	TSTNRM		; GO NORMALIZE IF REQUIRED
	BRA	3F		; ...and done
1
	CMPD	#$3FFF		; Infinity or NaN?
	BNE	1F		; No...
	LSL	FRACT,X		; ASSURE THAT MSB OF FRACT IS 0
	LSR	FRACT,X
	LDD	#$7FFF		; EXPONENT = #$7FFF
	STD	EXP,X
	LBSR	TFRACT		; SEE IF FRACTION = 0
	BNE	2F		; No, it's a NaN.
	LDA	#TYINF		; TYPE := INFINITY
	STA	TYPE,X
	BRA	3F
2	; {NaN}
	LBSR	DONAN		; GO DO NAN PROCESSING
	BRA	3F
1	; {PLAIN OLD NUMBER}
	LSLA			; CONVERT 15 TO 16 BIT SIGNED EXPONENT
	ASRA
	STD	EXP,X		; SAVE EXPONENT
	TST	FRACT,X		; Normalized?
	BLT	3F		; Yes, get out.
	LDA	#TYNNRM		; TYPE := NOT NORMALIZED
	STA	TYPE,X
3
	RTS

;*****************************************************************
;
;  M O V E  R E S U L T
;
;  MOVE RESULT ON STACK FRAME TO USER MEMORY. DO THE
;  NECESSARY COMPACTION TO MEMORY FORMAT.
;
;  ON ENTRY:
;    X = POINTER TO RESULT IN USER MEMORY
;    U = POINTER TO STACK FRAME
;
;  ON EXIT:
;    ALL REGISTERS RESTORED
;
;*****************************************************************
;
; THE MAIN PART OF MOVERESULT DETERMINES THE PRECISION OF THE ARGUMENT
; AND THEN CALLS THE APPROPRIATE SUBROUTINE TO HANDLE THAT
; PRECISION ARGUMENT.
;
; XXXJRT We could make this routine a teensy bit smaller and faster
; by putting the restore-and-return as a fall-through in the Single
; case and make the others back-branch to it.
;
MOVRSL
	PSHS	D,Y,CC
	LEAY	RESULT,U	; GET PTR TO RESULT ON STACK
	LDB	RPREC,U		; GET PRECISION OF RESULT
	BNE	1F		; Not single..
	BSR	PUTSGL		; SINGLE
	BRA	2F
1
	CMPB	#DBL		; Double?
	BNE	1F		; Not double...
	BSR	PUTDBL
	BRA	2F
1
	LBSR	PUTEXT		; Must be extended.
2
	PULS	D,Y,CC,PC	; RETURN

;*****************************************************************
;
;  PUTSGL - STORE SINGLE RESULT IN EXTERNAL MEMORY
;
;    MOVE RESULT FROM INTERNAL STACK FRAME TO EXTERNAL
;    RESULT. DO THE NECESSARY COMPACTION
;
;  ON ENTRY:
;    Y = POINTER TO RESULT ON STACK FRAME
;    X = POINTER TO RESULT IN USER MEMORY
;
;  ON EXIT:
;    D AND CC ARE MODIFIED
;
;*****************************************************************
PUTSGL
	; MOVE FRACTION OVER
	LDD	FRACT,Y		; GET 16 MSB OF FRACTION
	LSLA			; SHIFT OUT 1.0 BIT. WILL BE SHIFTED RIGHT LATER
	STD	1,X
	LDA	FRACT+2,Y	; MOVE LSB OF FRACTION
	STA	3,X
	LDD	EXP,Y		; GET EXPONENT
	; LOOK FOR SPECIAL CASES
	CMPD	#$8000		; Zero?
	BNE	1F		; No.
	CLRA			; SET EXPONENT = 0
	BRA	2F
1
	CMPD	#$7FFF		; Infinity or NaN?
	BNE	1F		; No.
	CLRA			; SET EXP = MAX($00FF)
	BRA	2F
1	; {NORMALIZED OR DENORMALIZED}
	ADDD	#SBIAS		; ADD BIAS
	CMPD	#1		; IF EXP=1 THEN IT MIGHT BE DENORMALIZED
	BNE	2F		; No.
	TST	FRACT,Y		; MS fraction bit set?
	BLT	2F		; Yes, skip.
	CLRB			; D=0
2
	LSRB			; SHIFT LSB OF EXP INTO C
	ROR	1,X		; AND INTO FRACTION
	ORB	SIGN,Y		; SET SIGN
	STB	,X		; STORE EXPONENT AND SIGN
	RTS

;*****************************************************************
;
;  PUTDBL - STORE DOUBLE RESULT IN EXTERNAL MEMORY
;
;    MOVE RESULT FROM INTERNAL STACK FRAME TO EXTERNAL
;    RESULT. DO THE NECESSARY COMPACTION
;
;  ON ENTRY:
;    Y = POINTER TO RESULT ON STACK FRAME
;    X = POINTER TO RESULT IN USER MEMORY
;
;  ON EXIT:
;    D AND CC ARE MODIFIED
;
;*****************************************************************
;
; MACRO USED TO SHIFT DOUBLE RESULT FRACTION
; 1 BIT RIGHT.
;
RIGHT1	macro
	LSRA
	RORB
	ROR	3,X
	ROR	4,X
	ROR	5,X
	ROR	6,X
	ROR	7,X
	endm

;
; ENTER HERE
;
PUTDBL
	BSR	MOVIT		; MOVE FRACTION TO USER MEMORY
	; POSITION FRACTION IN WORD
	LDD	1,X		; GET FIRST 2 BYTES OF FRACTION
	ANDA	#$7F		; CLEAR OUT 1.0 BIT
	RIGHT1			; SHIFT WHOLE THING RIGHT 3 BITS
	RIGHT1
	RIGHT1
	STD	1,X		; RESTORE FIRST 2 BYTES OF FRACTION
	LDD	EXP,Y		; GET EXPONENT
	; LOOK FOR SPECIAL CASES
	CMPD	#$8000		; Zero?
	BNE	1F		; No.
	CLRA			; SET EXPONENT = 0
	BRA	2F
1
	CMPD	#$7FFF		; Infinity or NaN?
	BNE	1F		; No.
	LDA	#$7		; SET EXP = MAX($07FF)
	BRA	2F
1	; {NORMALIZED OR DENORMALIZED}
	ADDD	#DBIAS		; ADD BIAS
	CMPD	#1		; IF EXP=1 THEN IT MIGHT BE DENORMALIZED
	BNE	2F		; No.
	TST	FRACT,Y		; MS fraction bit set?
	BLT	2F		; Yes, skip.
	CLRB			; D=0
2
	SLD4			; SHIFT EXPONENT LEFT 4
	ORB	1,X		; OR IN 4 MSB'S OF FRACTION
	ORA	SIGN,Y
	STD	,X
	RTS

;
; MOVIT - LOCAL SUBROUTINE TO MOVE 7 BYTE FRACTION
;         FROM 'FRACT,Y' TO '1,X'.
; DESTROYS D
;
MOVIT
	LDD	FRACT,Y
	STD	1,X
	LDD	FRACT+2,Y
	STD	3,X
	LDD	FRACT+4,Y
	STD	5,X
	LDD	FRACT+6,Y
	STD	7,X

;*****************************************************************
;
;  PUTEXT - STORE EXTENDED RESULT IN EXTERNAL MEMORY
;
;    MOVE RESULT FROM INTERNAL STACK FRAME TO EXTERNAL
;    RESULT. DO THE NECESSARY COMPACTION
;
;  ON ENTRY:
;    Y = POINTER TO RESULT ON STACK FRAME
;    X = POINTER TO RESULT IN USER MEMORY
;
;  ON EXIT:
;    D AND CC ARE MODIFIED
;
;*****************************************************************
PUTEXT
	LEAX	1,X		; MOVE FRACTION TO EXTERNAL MEMORY
	BSR	MOVIT
	LDA	FRACT+7,Y	; MOVE 8TH BYTE
	STA	8,X
	LEAX	-1,X		; RESTORE X
	LDD	EXP,Y		; GET EXPONENT
	; LOOK FOR SPECIAL CASES
	CMPD	#$8000		; Zero?
	BNE	1F		; No.
	LSRA			; SET EXPONENT = #$4000
	BRA	2F
1
	CMPD	#$7FFF		; Infinity or NaN?
	BNE	1F		; No.
	LSRA			; SET EXPONENT = #$3FFF
	BRA	2F
1	; {NORMALIZED OR DENORMALIZED}
	ANDA	#$7F		; CLEAR SIGN BIT
2
	ORA	SIGN,Y		; SET SIGN
	STD	,X		; SAVE EXPONENT
	RTS

;*****************************************************************
;
;  T R A P
;
;    CHECK FOR ENABLED TRAPS. GO TO TRAP HANDLER IF TRAP FOUND.
;    IF TRAP OCCURS, THE TRAP HANDLER WILL RECEIVE AN INDEX
;    IN THE A-REGISTER OF:
;       0  INVALID OPERATION
;       1  OVERFLOW
;       2  UNDERFLOW
;       3  DIVIDE BY ZERO
;       4  UNORDERED
;       5  INTEGER OVERFLOW
;       6  INEXACT
;
;    IF MORE THAN ONE ENABLED TRAP OCCURED, THE ONE WITH THE
;    HIGHEST PRIORITY IS TAKEN. 0 HAS HIGHEST PRIORITY AND
;    6 THE LOWEST.
;
;    FOR COMPARES THAT TRAP ON UNORDERED, UNORDERED WILL
;    WILL BE ENABLED FOR THE DURATION OF THIS
;    ROUTINE (NOT PERMANENTLY).
;
;
;  ON ENTRY:
;    U POINTS TO STACK FRAME
;
;  ON EXIT:
;    C = 1 IF NO TRAP OCCURED OR USER TRAP HANDLER WANTS
;          US TO CONTINUE WITH THE ARGUMENT.
;    C = 0 IF TRAP OCCURED AND USER DOES NOT WANT US TO
;          RETURN A RESULT OR TO CONTINUE.
;    CC IS DESTROYED ON EXIT
;
;*****************************************************************
TRAP
	TST	TSTAT,U		; DO A QUICK EXIT IF NO BITS ARE SET
	BNE	1F
	ORCC	#C		; Set Carry.
	RTS			; Peace out.
1
	PSHS	D,X
	LDX	PFPCB,U		; GET POINTER TO FPCB
	LDD	TSTAT,U		; GET BOTH STATUS BYTES
	BITA	#ERRIOP		; IOP ERROR?
	BEQ	1F		; No, skip...
	STB	SS,X		; STORE SECONDARY STATUS
1
	ORA	ERR,X		; OR IN CURRENT STATUS BITS
	STA	ERR,X		; STORE IN USER'S FPCB
	LDB	ENB,X		; GET ENABLE BITS
	LDA	FUNCT,U		; GET FUNCTION CODE
	BITA	#TONUN		; Trap on unordered compare?
	BEQ	1F		; No, skip...
	ORB	#ENBUN		; ENABLE UNORDERED TRAP
1
	ANDB	TSTAT,U		; AND WITH ERROR STATUS FROM THIS OPERATION
	BEQ	1F		; No traps enabled...
	LDA	#-1		; INIT FOR LOOP INDEX
2
	INCA			; INCR INDEX
	LSRB			; FOUND HIGHEST ENABLED TRAP?
	BCC	2B		; LOOP IF NOT
	PSHS	X,Y,U,D		; PROTECT REGS FROM USER
	JSR	[TRAPV,X]	; GO TO USER TRAP HANDLER
	PULS	X,Y,U,D		; RESTORE REGS
	BRA	2F		; User trap handler sets Carry as desired.
1
	ORCC	#C		; CARRY = 1 = NO TRAP OCCURED
2
	LDD	#0		; CLEAR OUT TEMP STATUS
	STD	TSTAT,U
	PULS	X,D,PC

;*****************************************************************
;
; I R E G
;
;   INITIALIZE THE STACK FRAME ON A REGISTER CALL. CREATE THE
;   STACK FRAME AND INITIALIZE MANY OF THE LOCATIONS IN THE
;   STACK FRAME.
;
;   ON ENTRY:
;      A CONTAINS THE FUNCTION NUMBER
;      X CONTAINS TPARAM IF MOVE OR COMPARE
;
;   ON EXIT:
;      ALL REGISTERS RESTORED
;      U-REG POINTS TO NEWLY CREATED STACK FRAME
;
;*****************************************************************
IREG
	LEAS	-FRMSIZ,S	; CARVE OFF SPACE FOR STACK FRAME
	LDU	DREG,S		; LOAD PTR TO FPCB
;
;   MUTUAL CODE ALSO SHARED BY ISTACK.
;   ASSUMES D IS ON THE STACK WHEN ENTERING HERE
;
IXIT
	STU	PFPCB,S		; STORE PTR TO FPCB
	STA	FUNCT,S		; SAVE FUNCTION NBR.
	STX	TPARAM,S	; SAVE PARAMETER WD (IF ANY)
; CLEAR ALL STACK FRAME ENTRIES FROM 'TYPE1'
; DOWN TO AND INCLUDING STIKY
	LEAU	TYPE1+1,S	; GET PTR TO TOP OF AREA TO CLEAR
	PSHS	D,X,Y		; SAVE REGS
	LDD	#0		; D=0
	LDX	#0		; D,X, AND Y ARE CLEARED (6 BYTES)
	LEAY	,X		; Y=0 TOO
; FAST CLEAR TAKES 75 CYLES
	PSHU	D,X,Y
	PSHU	D,X,Y		; 6 * 6 = 36 BYTES
	PSHU	D,X,Y
	PSHU	D,X,Y
	PSHU	D,X,Y
	PSHU	D,X,Y
	PSHU	D,X		; + 4 MORE MAKES 40
	LEAU	6,S		; U NOW POINTS TO STACK FRAME
	STX	TSTAT,U		; CLEAR TSTAT
	INCB			; B=1 (RESULT PRECISION)
	LBSR	PREC		; GET PRECISION OF RESULT
	STB	RPREC,U
	PULS	D,X,Y		; RESTORE REGS
	JMP	[ISTKPC,U]	; RETURN THRU PC ON STACK

;*****************************************************************
;
; I S T A C K
;
;   INIT STACK FRAME FOR STACK CALL. RESERVES SPACE ON THE
;   STACK AND INITIALIZES SOME VARIABLES.
;
;   ON ENTRY;
;     A CONTAINS THE FUNCTION NBR.
;     Y CONTAINS A POINTER TO THE TOP OF STACK (TOS). ASSUMES
;       THE POINTER TO THE FPCB IS AT TOS-2
;
;   ON EXIT:
;     U-REG POINTS TO STACK FRAMES
;     ALL OTHER REGISTERS RESTORED EXCEPT CC
;
;*****************************************************************
ISTACK
	LEAS	-FRMSIZ,S	; CARVE OFF SPACE FOR STACK FRAME
	STY	PTOS,S		; SAVE TOS PTR
	LDU	-2,Y		; LOAD PTR TO FPCB
	BRA	IXIT		; GO TAKE MUTUAL EXIT WITH IREG

;*****************************************************************
;
; C L S T A K
;
;  CLOSE STACK FRAME. POP THE WHOLE STACK FRAME OFF OF THE STACK
;  BACK TO THE USER'S CCREG
;
;  CAUTION: ANYTHING ON THE STACK BELOW THE STACK
;           FRAME WILL BE LOST
;
;  X IS DESTROYED
;
;*****************************************************************
CLSTAK
	LDX	,S		; GET RETURN ADDRESS
	LEAS	,U		; CARVE UP TO U
	LEAS	FRMSIZ+2,S	; POP STACK FRAME PLUS IREGPC OR ISTKPC
	JMP	,X		; EXIT
