;
; TTL  ROUND AND OVERFLOW/UNDERFLOW ROUTINES
; NAM  EXEPRND
;
; LINKING LOADER ROUTINES
;
; XDEF	ROUND,ADBIAS,SUBIAS,CHKOVF,CHKUNF
;
; XREF	MINTBL,MAXTBL,CLRES,DNMTBL
;
; REVISION HISTORY:
;   DATE	PROGRAMMER     REASON
;
;  23.MAY.80	G. STEVENS     ORIGINAL
;  22.JUL.80	G. STEVENS     FIX UNDERFLOW FOR ZEROEX
;  30.JUL.80	G. WALKER      REALLY FIX UNDERFLOW
;  03.AUG.80	G. STEVENS     ROUND ZEROS BEYOND RPREC
;  21.AUG.80	G. STEVENS     SET UNF AND OVF FLAGS IN CHKUNF
;			       AND CHKOVF
;  21.AUG.80	G. STEVENS     SET INEXACT IF ROUNDING NEEDED
;  22.AUG.80	G. STEVENS     CHANGE CONDITIONALS IN CHKUNF&CHKOVF
;  25.AUG.80	G. STEVENS     CHANGE EXP. TABLE & CONDITIONAL IN CHKOVF
;  27.JUN.22    @thorpej       Updated for asm6809.  New comments
;                              are in mixed-case.
;
;*****************************************************************
;
;  SUBROUTINE ROUND
;
;   ROUND HANDLES THE ROUNDING OPERATIONS
; ON THE FLP RESULT. THE TYPE OF ROUNDING
; SUPPORTED INCLUDE:
;
;   RM - ROUND TO MINUS INFINITY
;   RN - ROUND TO PLUS INFINITY
;   RN - ROUND TO NEAREST
;   RZ - ROUND TO ZERO
;
;   THIS ROUTINE SUPPORTS ALL PRECISION
; FORMATS I.E. SINGLE, DOUBLE, EXTENDED
; AND EXTENDED WITH FORCED ROUNDING.
;
;
;BEGIN
;
; DECIDE PRECISION MODE
;
ROUND
	LDB	RPREC,U
	;
	; FIX UP THE STIKY BYTE
	;
	LSRB			; HALF THE RETURNED PRECISION INDEX
	LEAY	SFIX_rnd,PCR	; MASK TABLE FOR ROUND BITS
	LDA	B,Y		; GET THE ROUND BIT MASK
	PSHS	A		; SAVE IT
	;
	; NOW FIND THE G-BIT OF THE FRACTION
	;
	LSLB
	LSLB			; QUADRUPLE PRECISION INDEX
	;
	; POINT Y TO CORRECT POSITION IN THE OFFSET TABLE
	;
	LEAY	SINGLE,PCR
	LEAY	B,Y

	LDB	0,Y		; OFFSET TO G-BYTE
	LDA	B,X		; GET G-BYTE
	;
	; PROCEED TO CORRECT THE STKIY BYTE BY ORING IN
	; THE ROUND BITS IN THE FRACTION WITH THE STIKY
	; BYTE.
	;
	ANDA	0,S		; CORRECT MASK IS ON THE STACK
	ORA	STIKY,U
	STA	STIKY,U
	LEAS	1,S		; CLEAN UP THE STACK
	;
	; NOW THAT THE PRECISION IS KNOWN AND THE STIKY
	; BYTE HAS BEEN CORRECTED DECIDE IF ROUNDING IS
	; NEEDED.
	;
	LDA	B,X		; GET G-BYTE
	ANDA	1,Y		; GET G-BIT
	ORA	STIKY,U		; OR IN STIKY BYTE
	;
	; IF ROUNDING IS NEEDED THEN CASE( ROUNDING MODE)
	; TO DETERMINE DESIRED ROUNDING OERATIONS.
	;

	; I've restructured this to flow a bit better.  The use of
	; the IF-ELSE-ENDIF macros made this function particularly
	; difficult to read.  --thorpej

	BEQ	ROUND_out	; Rounding not needed, get out.

	LDA	TSTAT,U		; SET INEXACT RESULT
	ORA	#ERRINX
	STA	TSTAT,U

	LDA	[PFPCB,U]	; GET CONTROL WORD
	ANDA	#CTLRND		; ISOLATE ROUNDING INFO

	;
	; OK, A contains the rounding mode.  It's 2 bits, 4 total
	; values.  The default mode is Round-to-nearest, so we'll
	; test for that first.  We only need to check for 3 of
	; them cause the 4th value can be inferred.  There is a
	; common tail that each rounding mode needs to branch to
	; after it's done its work.
	;
	; (Could use a jump table here, but it would be larger than
	; just doing the compares-and-brach.)
	;
	CMPA	#RN		; Round-to-nearest?
	BEQ	ROUND_rn
	CMPA	#RZ		; Round-to-zero?
	BEQ	ROUND_rz
	CMPA	#RP		; Round-to-plus-infinity?
	BEQ	ROUND_rp

	; Default case is Round-to-minus-infinty.

	;
	; IF SIGN IS NEG., ADD 1 TO L
	; If we don't need to perform the add, then we
	; can just branch right to ROUND_done.
	;
	LDA	SIGN,X
	BGE	ROUND_done
	;
	; GET OFFSET TO L BYTE(REG. B) AND THE ONE TO
	; CONSTANT(REG. A).
	;
	LDD	2,Y
	;
	; PERFORM A MULTIPRECISION 1 TO L ADD
	;
	BSR	MPADD
	BRA	ROUND_done

	; Round-to-plus-infinity
ROUND_rp
	;
	; IF SIGN IS POS., ADD 1 TO L
	; If we don't need to perform the add, then we
	; can just branch right to ROUND_done.
	;
	LDA	SIGN,X
	BLT	ROUND_done
	;
	; GET OFFSET TO L BYTE(REG. B) AND THE ONE TO
	; CONSTANT(REG. A).
	;
	LDD	2,Y
	;
	; PERFORM A MULTIPRECISION 1 TO L ADD
	;
	BSR	MPADD
	BRA	ROUND_done

	; Round-to-nearest
ROUND_rn
	;
	; IF G = 1 AND(R = S = 1 OR L = 1) THEN
	; ADD 1 TO G
	;
	LDB	0,Y		; GET OFFSET TO G BYTE
	LDA	B,X		; LOOK AT G BYTE
	ANDA	1,Y		; LOOK AT G BIT
	BEQ	ROUND_done	; G == 0, done.
	LDA	STIKY,U		; LOOK AT STIKY BYTE
	BNE	1F		; R & S <> 0
	LDB	2,Y		; GET OFFSET TO L BYTE
	LDA	B,X		; LOOK AT L BIT
	ANDA	3,Y		; CHECK L BIT
	BNE	1F		; L BIT <> 0
	BRA	ROUND_done	; R,S,L all 0, done.
1
	;
	; IF G( RS + L ) = 1  THEN ADD ONE THE G - BIT
	;
	; GET OFFSET TO G BYTE( REG. A ) AND THE ONE TO
	; G CONSTANT( REG. B ).
	;
	LDD	0,Y
	;
	; PERFORM A MULTI PRECISION ONE TO G ADD
	;
	BSR	MPADD
	; FALLTHROUGH to ROUND_done

	; Round-to-zero.  Which is about as simple as you can get.
ROUND_rz
ROUND_done
	;
	; FLUSH OUT STACK FRAME ARGUMENT BEYOND ITS PRECISION
	;
	LDB	RPREC,U		; PRECISION INDEX
	LBSR	CLRES		; Clear insignificant bytes.
ROUND_out
	RTS			; RETURN

;
; HERE IS A TABLE CONTAINING THE BYTE AND
; BIT LOCATIONS OF THE L AND G-BITS FOR
; THE VARIOUS PRECISION MODES. SUBROUTINE
; ROUND OPERATES AS A TABLE INTERPERTER
; USING THIS TABLE.
;
SINGLE	FCB	FRACT+3		; BYTE OFFSET TO G
	FCB	BIT7		; BIT LOCATION OF G
	FCB	FRACT+2		; BYTE OFFSET TO L
	FCB	BIT0		; BIT LOCATION OF L

DOUBLE	FCB	FRACT+6		; BYTE OFFSET TO G
	FCB	BIT2		; BIT LOCATION OF G
	FCB	FRACT+6		; BYTE OFFSET TO L
	FCB	BIT3		; BIT LOCATION OF L

EXTND	FCB	FRACT+8		; BYTE OFFSET TO G
	FCB	BIT7		; BIT LOCATION OF G
	FCB	FRACT+7		; BYTE OFFSET TO L
	FCB	BIT0		; BIT LOCATION OF L

EXTFTS	FCB	FRACT+3		; BYTE OFFSET TO G
	FCB	BIT7		; BIT LOCATION OF G
	FCB	FRACT+2		; BYTE OFFSET TO L
	FCB	BIT0		; BIT LOCATION OF L

EXTFTD	FCB	FRACT+6		; BYTE OFFSET TO G
	FCB	BIT2		; BIT LOCATION OF G
	FCB	FRACT+6		; BYTE OFFSET TO L
	FCB	BIT3		; BIT LOCATION OF L
;
; HERE IS THE TABLE OF GET ROUND BIT MASKS
;
SFIX_rnd
	FCB	$7F		; SINGLE
	FCB	BIT0+BIT1	; DOUBLE
	FCB	$7F		; EXTENDED
	FCB	$7F		; EXT. FORCE TO SINGLE
	FCB	BIT0+BIT1	; EXT. FORCE TO DOUBLE

;*****************************************************************
;
; SUBROUTINE  MPADD
;
;    MPADD PERFORMS A MULTI-PRECISION ADDITION
; OF AN 8-BIT OPERAND WITH THE SIGNIFICAND
; OF A FLOATING OPERAND. THE 8-BIT QUANTITY
; IS ADDED TO THE LSBYTE OF THE SIGNIFICAND
; WHICH IS SPECIFIED BY AN OFFSET PASSED IN
; IN THE B-REG. OVERFLOW CHECKING IS PROVIDED
; ASSUMING UNSIGNED OPERANDS. IF OVERFLOW DOES
; OCCUR THEN THE SIGNIFICAND IS RIGHT SHIFTED
; ONCE AND THE EXPONENT IS INCREMENTED.
;
; ON ENTRY:
;
;   B - CONTAINS THE 8-BIT OPERAND
;
;   X - POINTS TO THE ARGUMENT ON THE STACK FRAME
;
;   A - CONTAINS AN OFFSET TO THE LSBYTE OF THE
;	MULTI-PRECISION OPERAND.
;
;
; BEGIN
;
; ADD 8-BIT OPERAND TO LSBYTE OF OP2.
;
MPADD
	ADDB	A,X
	STB	A,X
	ANDB	#00		; CLEAR B, SAVE CCR
	;
	; PROPAGATE CARRY TO HIGHER ORDER BYTES
	; OF MULTIPRECISION OPERAND.
	;
	ROLB			; SAVE CARRY IN A
	DECA
1	CMPA	#FRACT
	BLT	1F
	TSTB
	BEQ	1F		; TERMINATE WHILE LOOP
	ADDB	A,X		; ADD IN CARRY
	STB	A,X
	ANDB	#00		; CLEAR B	XXXJRT use CLRB?
	ROLB			; SAVE CARRY IN B
	DECA
	BRA	1B
1
	;
	; CHECK FOR OVERFLOW; IF SO THEN RIGHT SHIFT
	; FRACTION AND INCREMENT EXPONENT.
	;
	TSTB
	BEQ	1F
	LDA	#FRACT
2	CMPA	0,Y
	BGE	2F
	RORB			; MOVE CARRY TO CC
	ROR	A,X
	ROLB			; SAVE CARRY IN B
	INCA
	BRA	2B
2
	LDD	EXP,X
	INCD
	STD	EXP,X
1
	RTS			; RETURN

;*****************************************************************
;
; SUBROUTINE ADBIAS
;
;   ADBIAS ADDS IN THE BIAS TO THE EXPONENT
; OF RESULT ON OVERFLOW. THE BIAS' ARE:
;
;	  SINGLE = 192
;	  DOUBLE = 1536
;	EXTENDED = 24576
;
;   ENTRY REQUIREMENTS:
;
;	U - CONTAINS POINTER TO STACK FRAME
;
;   ON EXIT:
;
;	A,B,X,- DESTROYED
;
;
; DETERMINE PRECISION MODE
;
ADBIAS
	PSHS	X,D		; SAVE CALLERS REGS.

	LDB  RPREC,U
	;
	; GET BIAS FOR THE GIVEN PRECISION
	;
	LEAX	BITBL,PCR
	ABX
	;
	; ADD BIAS TO EXPONENT
	;
	LDD	EXPR,U
	ADDD	0,X
	STD	EXPR,U

	PULS  X,D,PC		; RESTORE AND RETURN

;*****************************************************************
;
; SUBROUTINE  SUBIAS
;
;    SUBIAS SUBTRACTS THE BIAS FROM THE EXPONENT
; OF RESULT ON OVERFLOW. THE BIAS' ARE:
;
;	   SINGLE = 192
;	   DOUBLE = 1536
;	 EXTENDED = 24576
;
; ENTRY REQUIREMENTS:
;
;    U - CONTAINS POINTER TO STACK FRAME
;
; ON EXIT:
;
;    A,B,X - DESTROYED
;
;
; DETERMINE PRECISION MODE
;
SUBIAS
	PSHS	X,D		; SAVE CALLERS REGS.

	LDB	RPREC,U
	;
	; GET BIAS FOR GIVEN PRECISION MODE
	;
	LEAX	BITBL,PCR
	ABX
	;
	; SUBTRATCT BIAS FROM EXPONENT RESULT
	;
	LDD	EXPR,U
	SUBD	0,X
	STD	EXPR,U

	PULS	X,D,PC		; RESTORE AND RETURN

;
; HERE IS A TABLE OF UNDERFLOW/OVERFLOW
; ADJUST BIASES.
;
BITBL	FDB	192		; SINGLE
	FDB	1536		; DOUBLE
	FDB	24576		; EXTENDED
	FDB	192		; EXT. FORCE TO SINGLE
	FDB	1536		; EXT. FORCE TO DOUBLE

;*****************************************************************
;
; SUBROUTINE  CHKOVF
;
;   OVERFL TESTS A ROUNDED RESULT FOR AN
; OVERFLOW CONDITION. IF THE ROUNDED RESULT IS
; FINITE AND ITS EXPONENT IS TO LARGE FOR THE
; DESTINATION THEN OVERFLOW := TRUE; OTHERWISE
; OVERFLOW := FALSE.
;
; ENTRY REQUIREMENTS:
;
;  U - CONTAINS POINTER TO THE STACK FRAME
;
; EXIT REQUIREMENTS:
;
;  CC - Z BIT SET IF TRUE
;	Z BIT CLAERED IF FALSE
;
;   A,B,X - DESTROYED
;
; SEE IF EXPONENT IS FINITE
;
CHKOVF
	LDD	EXPR,U		; LOOK AT EXPONENT
	CMPD	#INFEX		; exponent == #INFEX?
	BEQ	1F		; Not finite -> no overflow
	;
	; GET PRECISION MODE
	;
	LDB	RPREC,U
	;
	; COMPARE EXPONENT RESULT TO MAX UNBIASED
	; EXPONENT
	;
	LEAX	MAXTBL,PCR	; MAX EXPONENT TABLE
	ABX
	LDD	EXPR,U
	CMPD	0,X		; D > max exponent?
	BLT	1F		; No -> no overflow

	LDA	TSTAT,U		; SET OVEFLOW FLAG
	ORA	#ERROVF
	STA	TSTAT,U
	ORCC	#Z		; OVERFLOW := TRUE
	RTS			; RETURN
1
	ANDCC	#NZ		; OVERFLOW := FALSE
	RTS

;*****************************************************************
;
;  SUBROUTINE  CHKUNF
;
;    UNDRFL TESTS A ROUNDED RESULT FOR AN
; OVERFLOW CONDITION. IF THE RESULTS
; EXPONENT IS TOO SMALL FOR THE DESTINATION
; THEN UNDERFLOW := TRUE; OTHERWISE
; OVERFLOW := FALSE.
;
; ENTRY REQUIREMENTS:
;
;    U - CONTAINS POINTER TO THE STACK FRAME
;
; ON EXIT:
;
;    CC - Z BIT SET IF TRUE
;	  Z BIT CLEARED IF FALSE
;
;    A,B,X - DESTROYED
;
; DETERMINE PRECISION MODE
;
CHKUNF
	LDB	RPREC,U
	LEAX	DNMTBL,PCR	; MIN. EXPONENT TABLE (denormalized)
	ABX
	;
	; IF EXPONENT NOT THAT OF A NORMAL ZERO THEN
	; COMPARE EXPONENT RESULT TO MINIMUM UNBIASED
	; EXPONENT.
	;
	LDD	EXPR,U		; EXPONENT OF RESULT
	CMPD	#ZEROEX		; D == #ZEROEX
	BEQ	1F		; Yes -> no underflow
	CMPD	0,X		; D < min exponent
	BGE	1F		; No -> no underflow

	LDA	TSTAT,U		; SET UNDERFLOW FLAG BYTE
	ORA	#ERRUNF
	STA	TSTAT,U
	ORCC	#Z		; UNDERFLOW := TRUE
	RTS			; RETURN
1
	ANDCC	#NZ		; UNDERFLOW := FALSE
	RTS