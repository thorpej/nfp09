;
;   NAM  FRMSQT
;   TTL  FLOATING-POINT REMAINDER ROUTINE
;
;    DEFINE EXTERNAL REFERENCES
;
; XDEF	FREM,FSQRT,SQINCK
;
; XREF	VALID,NORM1,NORMQK,FADD,XSUBY
; XREF	TFRACT,RTNAN,ROUND,FRCTAB,BITTBL
; XREF	FPMOVE,DNORM1,SHIFTR,IOPSUB,RTAR2
;
;
;    REVISION HISTORY:
;      DATE	   PROGRAMMER	    REASON
;
;    23.MAY.80	   G.WALKER	    ORIGINAL
;    1.JULY.80	   G.WALKER	    CODE COMPACTION
;    17.JUL.80	   G.WALKER	    MORE CODE SHRINK
;				      AND IOP SUBR.
;    18.JUL.80	   G.WALKER	    ADD 'SQINCK' BY G.S.
;    07.AUG.80	   G. STEVENS	    FIX GT TO GE IN SQINCK
;    15.OCT.80	   G.WALKER	    FIX CALL TO TFRACT IN FSQRT
;    17.DEC.80	   G.WALKER	    DO FINAL FPADD IN EXTENDED PREC.
;    28.JUN.22     @thorpej         Updated for asm6809.  New
;                                   comments are in mixed-case.
;
;*****************************************************************
;
;    FPREM --
;	 THIS ROUTINE CALCULATES THE REMAINDER OF
;    ARG1 / ARG2.  THE OPERATION IS DEFINED BY:
;	 RESULT = ARG1 - ARG2*N
;    WHERE N IS THE INTEGER NEAREST ARG1/ARG2 AND
;    N IS EVEN IF ABS(N - ARG1/ARG2) = 1/2. (I.E.
;    IT IS A TIE WHICH WAY TO ROUND)
;
;	 THE ACTUAL ALGORITHM USED TO FIND THE REMAINDER
;    INVOLVES CALCULATING ALL THE INTEGER BITS OF
;    THE RESULT IN A 'FUNNY DIVISION' LOOP.  THE
;    DIVIDEND LEFT OVER IS THE RAW REMAINDER, I.E.
;    THE REMAINDER OBTAINED BY TRUNCATION.  THE NUMBER
;    OF INTEGER BITS IN THE RESULT, WHICH IS THE
;    NUMBER OF DIVISION ITERATIONS THAT MUST BE
;    PERFORMED, IS OBTAINED FROM THE DIFFERENCE IN
;    EXPONENTS OF THE TWO ARGUMENTS.
;	 THE ACTUAL REMAINDER IS OBTAINED BY SIMULATING
;    A 'ROUND TO NEAREST' OPERATION ON THE QUOTIENT.
;    IF THE RAW REMAINDER IS LESS THAN HALF THE DIVISOR, THE
;    RESULT IS THE RAW REMAINDER.  IF THE RAW REMAINDER IS
;    GREATER THAN HALF THE DIVISOR, THE DIVISOR IS
;    SUBTRACTED ONCE MORE FROM THE RAW REMAINDER TO GIVE THE
;    RESULT.  IF THE RAW REMAINDER IS EQUAL TO HALF THE DIVISOR,
;    THEN THE SUBTRACTION IS PERFORMED ONLY IF THE LAST
;    BIT OF THE QUOTIENT WAS A ONE (WAS ODD).
;
;    LOCAL STORAGE:
;      FRCNDX (0) -- LARGEST INDEX INTO FRACTION
;      VBIT (1)   -- CARRY OUT OF HIGH-ORDER DIVIDEND
;      LSTBIT (2) -- LAST BIT OF INTEGER QUOTIENT GENERATED
;      QBITCNT (3) -- 2-BYTE COUNT OF QUOTIENT BITS GENERATED
;
FRCNDX	SET	0
VBIT	SET	1
LSTBIT	SET	2
QBITCNT	SET	3

FREM
	LEAS	-5,S		; RESERVE LOCAL STORAGE
	LDA	RPREC,U
	LSRA
	LEAX	FRCTAB,PCR	; GET LARGEST INDEX TO FRACTION
	LDB	A,X
	DECB			; CHANGE BYTE COUNT TO INDEX
	STB	FRCNDX,S
	;
	; CREATE COUNT OF INTEGER BITS IN QUOTIENT
	; AS DIFFERENCE OF ARGUMENT EXPONENTS + 1.
	;
	LDD	EXP1,U
	SUBD	EXP2,U
	ADDD	#1
	STD	QBITCNT,S
	;
	; CREATE POINTERS TO ARGUMENT FRACTIONS
	;
	LEAX	FRACT1,U
	LEAY	FRACT2,U
	;
	; DIVIDE ARG1 BY ARG2, GENERATING ALL THE INTEGER
	; QUOTIENT BITS (WHICH MAY BE A LARGE NUMBER OF THEM!!).
	; ONLY THE MOST RECENTLY GENERATED BIT IS SAVED.  EACH
	; TIME THE DIVIDEND IS LEFT SHIFTED, ITS EXPONENT IS
	; DECREMENTED BY ONE TO SO THAT THE VALUE OF THE
	; DIVIDEND IS NOT CHANGED BY THE SHIFT.
	;
	CLR	VBIT,S		; NO INITIAL CARRY
	CLR	LSTBIT,S	; INITIALLY CLEAR QUOTIENT
	; COUNT OF QUOTIENT BITS IS IN D-REG

	CMPD	#0		; LOOP TO GENERATE QUOTIENT BITS
	BLE	1F

	TST	VBIT,S		; IF CARRY OUT IS ZERO
	BNE	2F

	CLRA			; COMPARE FRACTIONS
	LDB	A,X

3	CMPB	A,Y		; UNLESS BYTES ARE UNEQUAL
	BNE	3F
	CMPA	FRCNDX,S	; IF ALL BYTES COMPARED, ARE EQUAL
	BGE	FRMSUB		; SO DO SUBTRACT
	INCA			; NEXT BYTE
	LDB	A,X		; FOR COMPARISON
	BRA	3B
3
	;
	; IF IT FELL OUT OF THE LOOP, THE THE CC REGISTER
	; TELLS THE RESULT OF THE COMPARISON.
	;
	BHI	FRMSUB		; DIVISOR WAS SMALLER, SO SUBTRACT
	CLR	LSTBIT,S	; ELSE GENERATE 0 QUOTIENT BIT
	BRA	FRMSHF		; AND NO SUBTRACT
2	; ^^ CARRY OUT IS EQUAL ZERO ^^

	;
	; GENERATE A QUOTIENT BIT OF '1' AND SUBTRACT THE
	; DIVISOR FROM THE DIVIDEND.
	;
FRMSUB
	LDA	#1
	STA	LSTBIT,S	; GENERATE A 1 AS QUOTIENT BIT
	LBSR	XSUBY		; SUBTRACT DIVISOR FROM DIVIDEND
	;
	; NOW SHIFT THE DIVIDEND FRACTION TO THE
	; LEFT ONE BIT, SAVING BIT SHIFTED OUT OF THE
	; MSBYTE IN 'VBIT'.  ALSO ADJUST QUOTIENT
	; BIT MASK TO GENERATE THE NEXT BIT.
	;
FRMSHF
	CLRA			; CLEAR CARRY
	; LSHIFT 0,X,9		; SHIFT DIVIDEND LEFT
	ROL     0+9-1,X
	ROL     0+9-2,X
	ROL     0+9-3,X
	ROL     0+9-4,X
	ROL     0+9-5,X
	ROL     0+9-6,X
	ROL     0+9-7,X
	ROL     0+9-8,X
	ROL     0+9-9,X
	LDB	#0
	ROLB			; SAVE CARRY OUT
	STB	VBIT,S
	LDD	EXP1,U		; DECREMENT EXPONENT TO COMPENSATE
	SUBD	#1		; FOR LEFT SHIFT
	STD	EXP1,U
	LDD	QBITCNT,S	; COUNT OF BITS GENERATED
	SUBD	#1
	STD	QBITCNT,S

	BRA	1B
1	; END LOOP TO GENERATE BINARY QUOTIENT

	;
	; IF THE OVERFLOW BIT (VBIT) IS SET, THEN
	; SHIFT IT RIGHT INTO ARG1 TO ALLOW COMPARISON
	; BETWEEN ARG1 AND ARG2.
	;
	LDB	VBIT,S
	BEQ	1F
	RORB			; PUT VBIT IN CARRY
	LEAX	-FRACT,X	; POINT TO FRACTION OF ARG1
	LBSR	DNORM1
	LEAX	FRACT,X		; POINT TO ALL OF ARG1
1
	;
	; IF THE REMAINDER (NOW IN ARG1) IS LESS
	; THAN HALF THE DIVISOR, THEN IT IS RETURNED
	; UNCHANGED AS THE RESULT.  IF THE REMAINDER
	; IS GREATER THAN HALF THE DIVISOR, THEN
	; THE DIVISOR IS SUBTRACTED FROM IT ONE MORE
	; TIME.  IF THE REMAINDER IS EQUAL TO HALF THE
	; DIVISOR, THEN THE SUBTRACTION IS PERFORMED
	; ONLY IF THE LAST INTEGER BIT IS A 1, I.E.
	; ROUND TO EVEN OF THE QUOTIENT IS SIMULATED.
	;
	LDD	EXP-FRACT,Y	; GET EXPONENT OF ARG2
	SUBD	#1

	CMPD	EXP-FRACT,X	; COMPARE TO EXP OF PARTIAL REM
	BLT	1F
	BGT	RMNOSB		; HALF REM GT DIVISOR, SO NO SUBTR.
	CLRA			; ELSE COMPARE FRACTIONS
	LDB	A,X

2	CMPB	A,Y
	BNE	2F

	CMPA	FRCNDX,S
	BLT	3F
	TST	LSTBIT,S
	BNE	RMSUB		; ROUND IF REM IS ODD
	BRA	RMNOSB		; DONT ROUND IF EVEN
3
	INCA
	LDB	A,X
	BRA	2B
2
	;
	; CC REG TELLS RESULT OF COMPARE IF THEY ARE
	; NOT EQUAL.
	;
	BLO	RMNOSB		; IF REM IS LESS, DONT SUBTRACT
1	; DIVISOR EXP. IS LESS

RMSUB
	LDA	SIGN-FRACT,X	; SET DIVISOR (ARG2) SIGN TO OPPOSITE
	EORA	#$80		; OF DIVIDEND (ARG1) SIGN
	STA	SIGN-FRACT,Y
	LDA	RPREC,U		; SAVE CURRENT ROUNDING MODE
	PSHS	A
	LDA	#EXT		; SET MODE TO EXTENDED (TO AVOID
	STA	RPREC,U		; SINGLE OR DOUBLE UNDERFLOW)
	LBSR	FADD		; SUBTRACT DIVISOR FROM RAW REMAINDER
	PULS	A		; RESTORE OLD ROUNDING MODE
	STA	RPREC,U
	BRA	RMEND

RMNOSB
	LEAY	RESULT,U	; MOVE RAW REMAINDER TO RESULT
	LEAX	ARG1,U
	LBSR	FPMOVE

RMEND
	;
	; NORMALIZE RESULT, IF NEEDED
	;
	LEAX	RESULT,U
	LBSR	NORMQK		; PERFORM MULTI-BIT NORMALIZE
	;
	; CHECK FOR EXCEPTIONS AND ROUND RESULT
	;
	LBSR	VALID		; VALIDATE RESULT
	;
	; CLEAN UP STACK AND SPLIT
	;
	LEAS	5,S
	RTS

; TTL  FLOATING-POINT SQUARE ROOT ROUTINE
;*****************************************************************
;
;    FSQRT --
;	 CALCULATES SQUARE ROOT OF ARG2 ON THE STACK,
;    LEAVING IT IN THE RESULT.	THE ALGORITHM IS
;    FROM:
;	 DAVID M. YOUNG AND R.T. GREGORY.  A SURVEY
;     OF NUMERICAL MATHEMATICS. VOL 1 (READING, MASS.:
;     ADDISON-WESLEY), 1972, PP. 61-62.
;
;    THE ALGORITHM FOR TAKING THE SQUARE ROOT OF THE
;    BINARY FRACTION MAY BE FOUND IN:
;	 HANS W. GESCHWIND AND EDWARD J. MCCLUSKEY.
;    DESIGN OF DIGITAL COMPUTERS. (NEW YORK: SPRINGER-
;    VERLAG), 1975, PP. 293-301.
;
;    LOCAL STORAGE:
;	 FRCNDX (0) -- LARGEST INDEX TO BYTE IN FRACTION
;	 FRBITS (1) -- NO. BITS IN FRACTION OF THIS PRECISION
;	 QBITCNT (2) -- COUNTER FOR RESULT BITS GENERATED
;	 VBIT	(3) -- HIGH-ORDER BIT OF ARG2.
;	 RSLBIT (4) -- BIT MASK FOR RESULT BIT TO BE GENERATED
;	 RSLNDX (5) -- INDEX OF BYTE FOR NEXT RESULT BIT
;	 TSTBIT (6) -- BIT MASK TO CREATE TEST VALUE BIT
;	 TSTNDX (7) -- BYTE INDEX WHERE TO CREATE TEST BIT
;
FRCNDX	SET	0
FRBITS	SET	1
QBITCNT	SET	2
VBIT	SET	3
RSLBIT	SET	4
RSLNDX	SET	5
TSTBIT	SET	6
TSTNDX	SET	7

FSQRT
	TST	ARG2,U		; Check for negative argument
	BEQ	1F
	IOP	1		; RETURN INVALID OP OF 1
	RTS			; Done.
1
	;
	; INITIALIZE LOCAL STORAGE
	;
	LEAS	-8,S
	LEAX	FRCTAB,PCR
	LDA	RPREC,U
	LSRA
	LDB	A,X
	DECB
	STB	FRCNDX,S	; INIT. LARGEST BYTE INDEX
	LEAX	BITTBL,PCR
	LDB	A,X
	STB	FRBITS,S	; INIT. NUMBER OF RESULT BITS
	;
	; CALCULATE SQUARE ROOT OF EXPONENT BY MAKING
	; IT EVEN AND THEN DIVIDING IT IN HALF.  IF EXPONENT
	; IS ODD, INCREMENT IT AND DENORMALIZE THE FRACTION
	; ONE BIT TO THE RIGHT SO THAT THE ARGUMENT IS NOT
	; CHANGED IN VALUE.
	;
	LEAX	FRACT2,U	; POINT TO ARGUMENT
	LEAY	FRACTR,U	; POINT TO RESULT

	LDD	EXP2,U
	LSRA			; DIVIDE EXPONENT BY 2
	RORB
	BCC	1F		; IF EXPONENT WAS ODD
	ADDD	#1		; INCR IT SO IS EVEN
	ANDCC	#$FE		; SHIFT 0 INTO FRACTION
	LBSR	SHIFTR		; FROM THE LEFT
1	; ^^^ EXPONENT WAS ODD ^^^
	STD	EXPR,U		; SAVE SQRT OF EXPONENT
	;
	; LOOP TO CALCULATE THE SQUARE ROOT OF THE
	; FRACTION, GENERATING ONE BIT OF THE RESULT FOR
	; EACH INTERATION.  THE OPERATION IS SIMILAR TO
	; A BINARY DIVISION, EXCEPT THAT THE PARTIAL
	; RESULT IS ITSELF USED AS THE TEST DIVISOR.
	;
	; THE TEST RESULT IS CREATED BY SETTING THE
	; BIT WHICH IS ONE PLACE TO THE RIGHT OF THE
	; BIT ABOUT TO BE GENERATED.  AFTER THE TEST
	; AND SUBTRACTION (IF ANY) IS PERFORMED, THE
	; TEST BIT IS REMOVED AND THE PROPER QUOTIENT
	; BIT IS INSERTED INTO THE RESULT.  THEN THE
	; ARGUMENT IS SHIFTED ONE PLACE TO THE LEFT, AND
	; THE QUOTIENT AND TEST BIT MASKS ARE MOVED ONE
	; BIT TO THE RIGHT.
	;
	; WHEN ALL FRACTION BITS HAVE BEEN GENERATED,
	; THE RESULT IS ROUNDED.
	;
	LDA	#$80
	STA	RSLBIT,S	; INIT. RESULT BIT MASK
	LSRA
	STA	TSTBIT,S	; INIT. TEST BIT MASK
	CLRA
	STA	RSLNDX,S	; INIT. RESULT BYTE INDEX
	STA	TSTNDX,S	; INIT. TEST BYTE INDEX
	STA	VBIT,S		; INIT. OVERFLOW BIT
	;
	; ALIGN ARGUMENT FRACTION WITH RESULT
	; RADIX POINT.
	;
	CLRA			; CLEAR CARRY BIT
	LBSR	SHIFTR
	;
	; NOW LOOP THE LOOP.
	;
	CLRA
	STA	QBITCNT,S

1	CMPA	FRBITS,S	; Loop to generate result bits.
	BGT	1F

	LDA	TSTNDX,S
	LDB	TSTBIT,S
	ORB	A,Y		; CREATE TEST VALUE
	STB	A,Y
	;
	; COMPARE TEST VALUE TO ARGUMENT.  IF TEST
	; IS SMALLER OR EQUAL,  SUBTRACT THE TEST VALUE
	; FROM THE ARGUMENT AND GENERATE A 1 BIT IN
	; THE RESULT.  OTHERWISE GENERATE A 0 BIT IN
	; THE RESULT.
	;
	TST	VBIT,S		; VBIT=1 MEANS ARGUMENT LARGER
	BNE	FSQSUB		; SO DO SUBTRACTION

	CLRA
	LDB	A,Y		; FIRST BYTE OF RESULT

2	CMPB	A,X
	BNE	2F
	CMPA	FRCNDX,S	; IF DIVIDEND EQUALS TEST VALUE
	BGE	FSQSUB		; DO SUBTRACTION
	INCA
	LDB	A,Y
	BRA	2B
2

	;
	; IF CONTROL FELL OUT OF THE LOOP, THEN
	; ARGUMENT IS NOT EQUAL TO RESULT AND THE
	; CC REGISTER TELLS THE COMPARISON.
	;
	BLO	FSQSUB		; SUBTRACT IF RESULT IS SMALLER
	BRA	FSQSHF		; AND GO DO SHIFT TO LEFT

FSQSUB
	LBSR	XSUBY		; SUBTRACT TEST FROM 'DIVIDEND'

	LDB	RSLNDX,S
	LDA	RSLBIT,S
	ORA	B,Y		; INSERT 1 AS RESULT BIT
	STA	B,Y
	;
	; SHIFT ARGUMENT LEFT BY ONE BIT AND
	; AJDUST MASKS FOR THE TEST AND RESULT BITS.
	;
FSQSHF
	LDA	TSTBIT,S
	LDB	TSTNDX,S	; REMOVE TEST BIT
	COMA
	ANDA	B,Y
	STA	B,Y
	CLRA			; CLEAR CARRY BIT
	; LSHIFT 0,X,9		; SHIFT ARG LEFT
	ROL     0+9-1,X
	ROL     0+9-2,X
	ROL     0+9-3,X
	ROL     0+9-4,X
	ROL     0+9-5,X
	ROL     0+9-6,X
	ROL     0+9-7,X
	ROL     0+9-8,X
	ROL     0+9-9,X
	LDB	#0
	RORB
	STB	VBIT,S		; SAVE HIGH-ORDER BIT

	CLRA			; CLEAR CARRY
	ROR	RSLBIT,S	; MOVE TO NEXT QUOTIENT BIT
	BCC	2F
	ROR	RSLBIT,S
	INC	RSLNDX,S	; MOVE TO NEXT QUO BYTE
2
	CLRA			; CLEAR CARRY
	ROR	TSTBIT,S	; MOVE TO NEXT TEST BIT
    	BCC	2F
	ROR	TSTBIT,S	; MOVE TO NEXT TEST BYTE
	INC	TSTNDX,S
2
	INC	QBITCNT,S
	LDA	QBITCNT,S

	BRA	1B
1			; LOOP TO GENERATE RESULT BITS

	;
	; SET STICKY BYTE NONZERO IF ARGUMENT
	; IS STILL NON ZERO.
	;
	LDB	FRCNDX,S
	INCB
	LEAX	-FRACT,X	; POINT TO ENTIRE INPUT ARGUMENT
	LBSR	TFRACT		; TEST ARG FRACTION FOR ZERO
	BEQ	1F		; AND SET STICKY <> 0 IF THERE
	INC	STIKY,U		; ARE ANY ONE BITS LEFT IN ARGUMENT
1
	LEAS	8,S		; REMOVE LOCAL STORAGE
	;
	; NORMALIZE RESULT LEFT ONE BIT IF NEEDED.
	;
	LEAX	RESULT,U
	LDA	FRACT,X
	BLT	1F		; IF MSB NOT SET
	LBSR	NORM1		; NORM. RESULT
1
	LBSR	ROUND		; ROUND TO APPROPRIATE PREC.
	RTS

;*****************************************************************
;
;    SQINCK --
;	 CHECKS INFINTIES AGAINST THE AFFINE AND
;    PROJECTIVE CLOSURE MODES WHEN PERFORMING A SQUARE
;    ROOT OPERATION.
;
;    ON ENTRY:
;	 U -- STAK FRAME POINTER.
;
;    ON EXIT:
;	 RESULT ON STACK FRAME CONTAINS EITHER ARG2 OR
;	     A NAN.
;	 U UNCHANGED.
;	 CC, D, X, Y ARE DESTROYED.
;
SQINCK
	LDA	[PFPCB,U]	; CHECK INFINITY CLOSURE MODE
	ANDA	#CTLAFF
	;
	; IF PROJECTIVE MODE THEN SIGNAL IOP=1 AND RETURN
	; A NAN.
	;
	BEQ	1F
	;
	; We're in AFFINE mode.  If ARG2 is +Inf, return ARG2.
	; Else, ARG2 is -Inf; signal IOP=1 and return a NaN.
	;
	LDA	SIGN2,U
	BLT	1F
	LBSR	RTAR2		; RETURN ARG2
	RTS
1
	IOP	1
	RTS
