; TTL FLOATING-POINT MULTIPLY OPERATION
; NAM  FMULDV
;
;      DEFINE EXTERNAL REFERENCES
;
; XDEF	FMUL,FDIV
;
; XREF	VALID,NORM1,GOSET,FPMOVE,DNORM1
; XREF	FRCTAB,BITTBL,XADDY
;
;
;    REVISION HISTORY:
;      DATE	    PROGRAMMER		REASON
;
;    23.MAY.80	    G.WALKER		ORIGINAL
;     1.JUL.80	    G.WALKER		CODE COMPACTION
;    13.JUL.80	    G.WALKER		SPEED & SHRINK
;    17.JUL.80	    G.WALKER		MORE SHRINK BY JOEL
;    14.AUG.80	    G.WALKER		DISALLOW NORMAL ZERO AS RESULT
;    06.OCT.80	    G.WALKER		ALLOW CALC. WHEN RESULT IS ZERO
;    14.OCT.80	    G.WALKER		CALCULATE FULL RESULT PRECISION
;    16.DEC.80	    G.WALKER		CORRECT STICKY LOOP INDEX
;    28.JUN.22      @thorpej            Updated for asm6809.  New comments
;                                       are in mixed-case.
;
;*****************************************************************
;
;    FMUL --
;	   THIS SUBROUTINE MULTIPLIES ARG1 AND ARG2 FROM
;    THE STACK FRAME, LEAVING THE PRODUCT IN RESULT.
;
;    THE RESULT SIGN IS THE EXCLUSIVE-OR OF THE SIGNS
;    OF THE TWO ARGUMENTS. THE RESULT EXPONENT IS THE SUM
;    OF THE TWO ARGUMENT EXPONENTS. (IT IS DECREMENTED BY
;    ONE TO ADJUST THE RADIX POINT OF THE RESULT MANTISSA.)
;    THE RESULT MANTISSA IS THE PRODUCT OF THE TWO
;    ARGUMENT MANTISSAS CALCULATED TO FULL PRECISION AND THEN
;    ROUNDED TO THE PRECISION OF THE ARGUMENTS.
;
;
;    THE MULTIPLICATION ALGORITHM IS:
;
;    *****   STAY TUNED *******
;
;
;    LOCAL STACK USAGE:      (OFFSET)
;	COL (0): INDEX TO POSITION IN RESULT MANTISSA
;	 AI (1): INDEX TO BYTE IN ARG 1 MANTISSA TO BE MULTIPLIED
;    MAXNDX (2): MAXIMUM INDEX INTO ARGUMENT PRECISION (SIGNIFICANT BYTE)
;    TMPRSL (3): 21-BYTE TEMPORARY RESULT (CALC. EXACTLY)
;
;    REGISTER USAGE:
;	D -- ARITHMETIC CALC. AND OFFSET INDEXING
;	Y -- ADDR. OF BYTE IN ARG2
;	X -- ADDR. OF BYTE IN ARG1
;	U -- STACK FRAME POINTER AND INDEX INTO RESULT
;	S -- STACK TOP POINTER
;
COL	EQU	0
AI	EQU	1
MAXNDX	EQU	2
TMPRSL	EQU	3

;
;     TABLE OF MAXIMUM INDEXES FOR ARGUMENT MANTISSAS
;  OF THE GIVEN PRECISION.
;
NDXTAB	FCB	2		; SINGLE
	FCB	6	 	; DOUBLE
	FCB	7		; EXTENDED
	FCB	2		; EXT. FORCED SINGLE
	FCB	6		; EXT. FORCED DOUBLE

FMUL
	LEAS	-24,S		; RESERVE LOCAL STORAGE
	LDA	RPREC,U		; GET MANT. SIZE INDEX
	LSRA			; DIVIDED BY 2
	LEAX	NDXTAB,PCR
	LDB	A,X		; GET MAX. INDEX INTO MANTISSA FROM TABLE
	STB	MAXNDX,S	; & SAVE ON STACK

	LDA	ARG1,U		; SIGN OF RESULT IS
	EORA	ARG2,U		; EXOR OF ARG SIGNS
	STA	TMPRSL+SIGN,S

	LDD	EXP1,U		; EXP OF RESULT IS
	ADDD	EXP2,U		; SUM OF ARG EXPS
	ADDD	#1
	STD	TMPRSL+EXP,S
	;
	; CLEAR OUT TEMP. RESULT MANTISSA
	;
	CLRA
	CLRB
	STD	TMPRSL+FRACT,S	; CLEAR PARTIAL PRODUCT ACC.
	STD	TMPRSL+FRACT+2,S
	STD	TMPRSL+FRACT+4,S
	STD	TMPRSL+FRACT+6,S
	STD	TMPRSL+FRACT+8,S
	STD	TMPRSL+FRACT+10,S
	STD	TMPRSL+FRACT+12,S
	STD	TMPRSL+FRACT+14,S
	;
	;    NOW MULTIPLY MANTISSAS TO FULL PRECISION, CREATING
	;  PARTIAL PRODUCTS IN EACH COLUMN FROM RIGHT TO LEFT.
	;
	LEAX	FRACT1,U
	LEAY	FRACT2,U

	LDB	MAXNDX,S
	ASLB			; MAX INDEX TIMES 2
	STB	COL,S		; IS RIGHTMOST COLUMN

1	CMPB	#0		; while B >= 0
	BLT	1F

	LEAU	TMPRSL+FRACT,S	; ***  MUST RESTORE U ***
	LEAU	B,U		; U-REG. POINTS TO COLUMN IN RESULT
	LDA	MAXNDX,S
	STA	AI,S		; INDEX INTO ARG1

2	CMPA	#0		; while A >= 0
	BLT	2F

	LDB	COL,S		; GET INDEX TO COLUMN OF RESULT
	SUBB	AI,S		; CREATE INDEX INTO ARG2

	CMPB	MAXNDX,S	; IS IT WITHIN RANGE?
	BGT	33F		; Nope.

	CMPB	#0
	BLT	5F
	LDA	A,X		; GET ARGUMENT BYTES AND MULTIPLY
	LDB	B,Y
	MUL
	ADDD	,U		; ADD PARTIAL PRODUCT INTO COLUMN
	STD	,U		; OF THE TEMPORARY RESULT
	BCC	5F
	INC	-1,U		; AND THROW CARRIES TO NEXT BYTE
5

	DEC	AI,S		; AND MOVE TO NEXT INDEX TO TEST ARG-BYTE PAIRS
	LDA	AI,S

	BRA	34F
33
	LDA	#-1		; TERMINATE LOOP IF MAX INDEX IS EXCEEDED
	STA	AI,S
34
	BRA	2B		; end while A >= 0
2
	LDB	COL,S		; NOW DO SAME FOR MEXT MOST SIGNIFICANT COLUMN
	DECB
	STB	COL,S

	BRA	1B		; end while B >= 0
1
	;
	;   NORMALIZE MANTISSA OF RESULT ONE BIT TO THE LEFT
	;	 IF NEEDED.
	;
	LEAU	-FRACT1,X	; RESTORE STACK FRAME POINTER
	LEAX	TMPRSL,S	; POINT X TO RESULT

	LDA	FRACT,X
	BLT	1F		; UNLESS MS-BIT IS A 1
	LBSR	NORM1		; NORMALIZE RESULT
1
	;
	;    ADJUST EXPONENT SO THAT A NORMAL ZERO
	;  WILL NOT SLIP BY, I.E. FORCE AN UNDERFLOW IN
	;  THE CASE THAT MULTIPLY PRODUCES A ZERO RESULT.
	;
	LDD	EXP,X		; IS RESULT EXPONENT MINIMUM?
	CMPD	#$8000
	BNE	1F
	LBSR	DNORM1		; ADJUST SO IT IS'NT MINIMUM.
1
	;
	; 'OR' BYTES BELOW GUARD BYTE INTO STICKY BYTE.
	;
	LEAX	FRACT,X		; POINT TO TEMP. RSLT FRACTION
	LDB	RPREC,U
	LEAY	GOSET,PCR
	LSRB
	LEAY	B,Y		; POINT Y TO INDEX OF GUARD BYTE
	LDB	MAXNDX,S
	ASLB			; START OR'ING AT RIGHTMOST BYTE
	INCB			; WHICH IS ONE BEYOND 2*MAXNDX
	CLRA			; INITIAL SITCKY IS ZERO

1	CMPB	0,Y
	BLE	1F
	ORA	B,X
	DECB
	BRA	1B
1
	STA	STIKY,U
	LEAX	-FRACT,X	; POINT TO ENTIRE RESULT
	;
	; COPY TEMPORARY RESULT ONTO STACK FRAME.
	;
	LEAY	RESULT,U
	LBSR	FPMOVE
	;
	;   ROUND RESULT AND CHECK
	;    FOR EXCEPTIONAL CONDITIONS
	;
	LBSR	VALID		; VALIDATE RESULT
	LEAS	24,S		; REMOVE LOCAL STORAGE
	RTS

;  TTL FLOATING-POINT DIVISION ROUTINE
;*****************************************************************
;
;    FDIV --
;	 DIVIDES ARG1 BY ARG2 AND STORES QUOTIENT IN
;    RESULT. RESULT SIGN IS EXCLUSIVE-OR OF THE
;    ARGUMENT SIGNS. RESULT EXPONENT IS EXP1 -EXP2.
;    THE RESULT FRACTION IS FORMED BY DIVIDING THE
;    FRACT1 BY FRACT2 USING A MODIFIED NON-RESTORING
;    BINARY DIVISION SIMILAR TO THAT IN
;	 GESCHWIND AND MCKLUSKEY, "DESIGN OF DIGITAL
;    COMPUTERS", PP. 278 FF.
;
;    LOCAL STORAGE:
;      FRCSIZ (0) -- NUMBER OF BYTES IN FRACTION
;      FRBITS (1) -- NUMBER BITS (+ GUARD) IN FRACT.
;      VBIT (2)  -- CARRY OUT OF HIGH-ORDER DIVIDEND
;      RSIND (3) -- INDEX OF RESULT BYTE RECEIVING
;		    CURRENTLY GENERATED QUOTIENT BIT
;      RSBIT (4) -- BIT MASK FOR QUOTIENT BIT BEING
;		    GENERATED
;      QBITCNT (5) -- COUNT OF QUOTIENT BITS GENERATED
;      (renamed from BITCNT to avoid collision with notrap.s)
;
FRCSIZ	SET	0
FRBITS	SET	1
VBIT	SET	2
RSIND	SET	3
RSBIT	SET	4
QBITCNT	SET	5

FDIV
	LEAS	-6,S		; RESERVE LOCAL STORAGE
	LDA	RPREC,U
	LSRA
	LEAX	FRCTAB,PCR	; GET LARGEST INDEX TO FRACTION
	LDB	A,X
	DECB			; CHANGE BYTE COUNT TO INDEX
	STB	FRCSIZ,S
	LEAX	BITTBL,PCR
	LDB	A,X
	STB	FRBITS,S	; STORE FRACTION BIT COUNT
	;
	; CREATE RESULT SIGN
	;
	LDA	ARG1,U
	EORA	ARG2,U
	STA	RESULT,U
	;
	; CREATE RESULT EXPONENT AS DIFFERENCE OF
	; ARGUMENT EXPONENTS.
	;
	LDD	EXP1,U
	SUBD	EXP2,U
	STD	EXPR,U
	;
	; DIVIDE FRACT1 BY FRACT2. THE RESULT FRACTION IS
	; CLEARED AND QUOTIENT BITS ARE DIRECTLY INSERTED INTO
	; THE PROPER PLACE IN THE RESULT. THE NUMBER OF BITS
	; GENERATED IS THE SIGNFICANT BITS + 1 GUARD BIT +
	; 1 ROUND BIT (IN CASE OF POSSIBLE LEFT SHIFT). IF
	; THE DIVIDEND IS NON-ZERO AT THAT POINT, THEN THE
	; STICKY BYTE IS ALSO SET NON-ZERO.
	;
	LEAX	FRACT1,U
	LEAY	FRACT2,U
	LEAU	FRACTR,U

	LDA	#$80		; INITIAL QUOTIENT BIT MASK
	STA	RSBIT,S
	CLRA
	STA	VBIT,S		; NO INITIAL CARRY
	STA	QBITCNT,S	; INITIALIZE BIT COUNT
	STA	RSIND,S		; INITIALIZE QUOTIENT BYTE TO GENERATE

1	CMPA	FRBITS,S	; LOOP TO GENERATE QUOTIENT BITS
	BGE	1F

	TST	VBIT,S		; IF CARRY OUT IS ZERO, COMPARE FRACTIONS
	BNE	FDOSUB

	CLRA
	LDB	A,X

2	CMPB	A,Y		; UNLESS BYTES ARE UNEQUAL
	BNE	2F
	CMPA	FRCSIZ,S	; IF ALL BYTES ARE COMPARED, THEN
	BGE	FDOSUB		;  FRACTS ARE EQUAL: DO SUBTR.
	INCA			; NEXT BYTE
	LDB	A,X		; FOR COMPARISON
	BRA	2B
2
	;
	; IF IT FELL OUT OF THE LOOP, THE THE CC REGISTER
	; TELLS THE RESULT OF THE COMPARISON.
	;
	BLO	FDSHFT		; UNLESS DIVISOR WAS LARGER

	;
	; GENERATE A QUOTIENT BIT OF '1' AND SUBTRACT THE
	; DIVISOR FROM THE DIVIDEND.
	;
FDOSUB
	LDA	RSIND,S		; GET BYTE INDEX
	LDB	RSBIT,S		; GET BIT MASK
	ORB	A,U		; OR '1' INTO RESULT
	STB	A,U

	XSBTRY			; SUBTRACT DIVISOR FROM DIVIDEND
	;
	; NOW SHIFT THE DIVIDEND FRACTION TO THE
	; LEFT ONE BIT, SAVING BIT SHIFTED OUT OF THE
	; MSBYTE IN 'VBIT'.  ALSO ADJUST QUOTIENT
	; BIT MASK TO GENERATE THE NEXT BIT.
	;
FDSHFT
	CLRA			; CLEAR CARRY
	; LSHIFT 0,X,9		; SHIFT DIVIDEND LEFT
	ROL	0+9-1,X
	ROL	0+9-2,X
	ROL	0+9-3,X
	ROL	0+9-4,X
	ROL	0+9-5,X
	ROL	0+9-6,X
	ROL	0+9-7,X
	ROL	0+9-8,X
	ROL	0+9-9,X
	LDB	#0
	ROLB			; SAVE CARRY OUT
	STB	VBIT,S
	ROR	RSBIT,S		; ROTATE QUOTIENT BIT MASK

	BCC	3F		; UNLESS THIS BYTE NOT FINISHED
	ROR	RSBIT,S		; ROTATE BIT INTO MSB OF MASK
	INC	RSIND,S		; AND MOVE TO NEXT QUOTIENT BYTE
3

	INC	QBITCNT,S	; INCR. COUNT OF BITS GENERATED
	LDA	QBITCNT,S

	BRA	1B
1				; END LOOP TO GENERATE QUOTIENT BITS

	;
	; ALL SIGNIFICANT BITS ARE GENERATED. NOW SET THE
	; STICKY BYTE TO NON-ZERO IF THE REMAINING PART OF
	; THE DIVIDEND IS NON-ZERO.
	;
	LEAU	-FRACTR,U
	CLRA
1	CMPA	FRCSIZ,S
	BGT	1F
	TST	A,X
	BEQ	2F
	LDA	#10		; IF DIVIDEND<>0, SET
	STA	STIKY,U		; STIKY BYTE AND...
	BRA	1F		; ...end loop.
2
	INCA
	BRA	1B
1
	;
	; NORMALIZE FRACTION ONE BIT TO LEFT, IF NEEDED.
	;
	LEAX	RESULT,U
	LDA	FRACT,X
	BLT	1F		; IF MSBIT NOT A ONE
	LBSR	NORM1		; NORMALIZE RESULT
1
	;
	; FORCE AN UNDERFLOW WHEN ZERO IS GENERATED AS A RESULT,
	; BY DISALLOWING A NORMAL ZERO TO PASS THROUGH.
	;
	LDD	EXP,X		; IF RESULT EXPONENT IS MINIMUM,
	CMPD	#$8000
	BNE	1F
	LBSR	DNORM1		; FIX IT SO EXPONENT IS'NT MINIMUM
1
	;
	; CHECK FOR EXCEPTIONS AND ROUND RESULT
	;
	LBSR	VALID		; VALIDATE RESULT
	;
	; CLEAN UP STACK AND SPLIT
	;
	LEAS 6,S
	RTS
