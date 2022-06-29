;
; NAM INTFLT
; TTL  FLOATING TO BINARY INTEGER CONVERSION
;
; LINKING LOADER DEFINITIONS
;
; XDEF GETINT,BIGINT,FFIX,FIXNAN,FLOAT,FIXZER
; XDEF  GOSET
;
; XREF ROUND,CLRES,SNORM,LNORM,PREC,ENORM,MOVE
; XREF  ZERO,IOPSUB,RTZERO,FPMOVE,FILSKY,DENORM
; XREF  TFRACT
;
; REVISION HISTORY:
;   DATE	PROGRAMMER	 REASON
;
;  23.MAY.80	GREG STEVENS	 ORIGINAL CREATION
;  12.JUN.80	G.STEVENS	 FIX & OPT. INTEGER
;  04.AUG.80	G. STEVENS	 FIX ALL INVOKATIONS OF ROUND
;  06.AUG.80	G. STEVENS	 FIX FFIX FOR ZERO AND CCREG
;  07.AUG.80	G. STEVENS	 ADD FIXZER & FIX FIXNAN
;  11.AUG.80	G. STEVENS	 CHANGE FIXNAN
;  13.AUG.80	G. STEVENS	 ADD UTILITY HOOKS IN INTEGER
;  08.OCT.80	G. STEVENS	 "GETINT" NOW IGNORES UNNRM ZEROS
;  09.OCT.80	G. STEVENS	 "GETINT" INVOKES FPMOVE VS MOVE
;  28.JUN.22    @thorpej         Updated for asm6809.  New comments
;                                are in mixed-case.
;
;*****************************************************************
;
;  HERE IS THE FUNCTION FCFIX WHICH TAKES A
; F.P. NUMBER AND CONVERTS IT TO A SIGNED BINARY
; INTEGER.
;
;
; PROCEDURE FFIX
;
;  FFIX CONVERTS A F.P. VALUE TO A BINARY INTEGER
; THE RESULT CAN BE EITHER A 16 OR 32 BIT SIGNED
; VALUE. IF THE RESULT OF THE CONVERSION WILL NOT
; FIT INTO THE DESTINATION THEN THE LARGEST INTEGER
; IS RETURNED.
;
FFIX
	;
	; GET THE INTEGER PART OF THE FLOATING OPERAND
	;
	LBSR	GETINT
	;
	; CONVERT INTEGER PART TO A BINARY INTEGER
	;
	LDA	FUNCT,U
	CMPA	#FCFIXS		; Fix single?
	BNE	1F		; No, must be fix double.
	LEAX	SINTSZ,PCR
	BRA	2F
1	LEAX	DINTSZ,PCR
2

	;
	; IF THE ARGUMENT HAS NO INTEGER PART JUST RETURN
	; ZERO AS THE BINARY INTEGER.
	;
	LDD	EXPR,U
	CMPD	#0
	BGE	1F		; Go handle integer part.
	; NO INTEGER PART
	LDD	#0
	STD	FRACTR,U
	STD	FRACTR+2,U

	LDA	CCREG,U		; SET Z BIT IN CCREG
	ORA	#Z
	ANDA	#($FF-(N+V+C))
	STA	CCREG,U
	BRA	3F		; Done.
1
	;
	; IF THE EXPONENT OF THE ARGUMENT IS LARGER
	; THAN THE INTEGER SIZE IN BITS THEN RETURN
	; THE LARGEST POSSIBLE INTEGER OF THE CORRECT
	; CORRECT SIZE.
	;
	CMPD	0,X		; Exponent too big?
	BLT	1F		; Nope.
	BSR	BIGINT
	BRA	3F		; Done.
1
	;
	; ELSE IF THE EXPONENT IS SUCH THAT THE INTEGER
	; WILL FIT INTO THE DESIRED DESTINATION THEN
	; RIGHT SHIFT THE EXPONENT UP AGAINST THE
	; PROPER BYTE BOUNDARY.
	;
	LEAY	FRACTR,U
1	CMPD	0,X
	BGE	1F
	ANDCC	#NC		; CLEAR CARRY
	; RSHIFT  0,Y,4
	ROR	0+0,Y
	ROR	0+1,Y
	ROR	0+2,Y
	ROR	0+3,Y
	INCD
	BRA	1B
1
	LDA	CCREG,U		; CLEAR BITS IN CCREG
	ANDA	#($FF-(N+C+V+Z))
	;
	; NOW CHECK THE SIGN OF THE ARGUMENT AND POSSIBLY
	; TAKE THE TWO'S COMPLEMENT OF THE RESULT SINCE
	; ORIGINALLY THINGS WERE SIGN AND MAGNITUDE.
	;
	LDB	ARG2,U
	BGE	2F		; Sign positive.
	; Sign negative.
	COM	0,Y
	COM	1,Y
	COM	2,Y
	NEG	3,Y
	BCS	1F
	INC	2,Y
	BNE	1F
	INC	1,Y
	BNE	1F
	INC	0,Y
1	ORA	#N		; SET N BIT IN CCREG
2	STA	CCREG,U		; REPLACE CCREG
3	RTS			; RETURN

*
* SIZE TABLE
*
SINTSZ	FDB	15
DINTSZ	FDB	31

;*****************************************************************
;
; PROCEDURE  BIGINT
;
;   BIGINT HANDLES A FFIX, FLOATING TO BINARY INTEGER
; CONVERSION WHEN THE ARGUMENT IS INFINITY OR THE
; PASSED F.P. VALUE IS TO BIG TO FIT INTO THE DESTINATION.
; THE INTEGER IS SET AS BELOW.
;
;      SHORT POSITIVE	 32767
;      SHORT NEGATIVE	-32768
;      LONG POSITIVE	2,147,483,647
;      LONG NEGATIVE   -2,147,483,648
;
;
;    ON ENTRY: U IS THE STACK FRAME POINTER
;
;    ON EXIT: FIRST TWO OR FOUR BYTES OF THE FRACTION
;	      CONTAIN THE BINARY INTEGER.
;
BIGINT
	;
	; CHECK THE SIGN OF THE ARGUMENT TO SEE WHETHER TO
	; RETURN A LARGE POSITIVE OR LARGE NEGATIVE NUMBER.
	;
	LDB	CCREG,U		; PREPARE TO SET CCREG PROPERLY
	ANDB	#($FF-(N+C+Z))
	ORB	#V
	STB	CCREG,U

	LDA	ARG2,U		; CHECK SIGN
	BLT	1F		; Go deal with negative sign.
	; Positive sign.
	LDD	LPINT,PCR
	STD	FRACTR,U
	LDD	LPINT+2,PCR
	STD	FRACTR+2,U
	BRA	2B
1	; Negative sign.
	LDB	CCREG,U
	ORB	#N
	STB	CCREG,U
	LDD	LNINT,PCR
	STD	FRACTR,U
	LDD	LNINT+2,PCR
	STD	FRACTR+2,U
2
	;
	; SET INTEGER OVERFLOW BIT IN MAIN STATUS
	;
	LDA	TSTAT,U
	ORA	#ERRIOV
	STA	TSTAT,U
	RTS			; RETURN

;
; INTEGER CONSTANTS
;
LPINT	FDB	$7FFF,$FFFF
LNINT	FDB	$8000,0000

;*****************************************************************
;
; PROCEDURE  FIXNAN
;
;    FIXNAN HANDLES A FFIX, FLOATING TO BINARY INTEGER
; CONVERSION WHEN THE ARGHUMENT IS A NAN. INVALID
; OPERATION (IOP = 3) IS SIGNALED AND THE NAN
; ADDRESS IS RETURNED IN THE PLACE OF THE INTEGER.
;
;  ON ENTRY: U IS THE STACK FRAME POINTER
;
;  ON EXIT: THE FIRST TWO BYTES OF THE FRACTION CONTAIN
;	   THE NAN ADDRESS.
;
FIXNAN
	;
	; SIGNAL INVALID OPERATION (IOP = 3)
	;
	LDD	#(256*ERRIOP)+3	; IOP CODE & IOP FLAG
	STD	TSTAT,U		; SECONDARY STATUS
	;
	; RETURN THE NAN ADDRESS
	;
	LEAX	ARG2,U		; SOURCE
	LEAY	RESULT,U	; DESTINATION
	LBSR	FPMOVE
	ANDCC	#NC		; CLEAR CARRY
	; LSHIFT FRACT,Y,3	; SHIFT ADDRESS TO NEAREST BYTE BOUNDARY
	ROL	FRACT+3-1,X
	ROL	FRACT+3-2,X
	ROL	FRACT+3-3,X
	; LSHIFT FRACT,Y,3
	ROL	FRACT+3-1,X
	ROL	FRACT+3-2,X
	ROL	FRACT+3-3,X
	;
	; RETURN CCREG WITH C BIT SET
	;
	LDA	CCREG,U
	ANDA	#($FF-(N+V+Z))
	ORA	#C
	STA	CCREG,U
	RTS			; RETURN

;*****************************************************************
;
; PROCEDURE FIXZER
;
;     HANDLES FIXES WHERE THE INPUT ARGUMENT IS ZERO
;
;  ON ENTRY: ARG2 CONTAINS THE INPUT ARGUMENT
;	     U - STACK FRAME POINTER
;
;  ON EXIT: RESULT CONTAINS THE RESULT
;	    U,S - UCHANGED
;	    X,Y,D,CC - DESTROYED
;
FIXZER
	;
	; SET Z BIT IN CCREG
	;
	LDA	CCREG,U
	ANDA	#($FF-(N+V+C))
	ORA	#Z		; SET Z BIT
	STA	CCREG,U
	;
	; RETURN A ZERO
	;
	LBSR	RTZERO		; XXXJRT tail-call?
	RTS			; RETURN

;*****************************************************************
;
; PROCEDURE GETINT
;
;    GETINT TAKES THE FLOATING OPERAND RESIDING
; IN ARG2  AND RETURN THE INTEGER PART AS  IT'S
; RESULT
;
; ON ENTRY: ARG2 CONTAINS THE INPUT ARGUMENT
;	    U - STACK FRAME POINTER
;
; ON EXIT: STACK FRAME RESULT CONTAINS THE INTEGER PART
;	   U - UNCHANGED
;	   X,Y,A,B,CC - DESTROYED
;
; LOCAL EQUATES
;
LOWBND	EQU	-2

GETINT
	;
	; FIRST MOVE THE ARGUMENT TO THE RESULT
	;
	LEAX	ARG2,U		; SOURCE
	LEAY	RESULT,U	; DESTINATION
	LBSR	FPMOVE
	;
	; CHECK FOR AN UNNORMAL ZERO AND IF THIS IS THE
	; CASE JUST RETURN THE ARGUMENT AS IS
	;
	LBSR	TFRACT
	BEQ	4F
	;
	; FIND PRECISION OF THE OPERAND
	;
	LDB	RPREC,U		; GET THE PRECISION INDEX
	PSHS	B		; SAVE PRECISION ON THE STACK
	;
	; IF THE EXPONENT IS LARGE ENOUGH SO THAT NO FRACTION
	; PART EXITS THEN JUST RETURN THE INPUT ARGUMENT AS IS
	;
	LEAX	SIGSIZ,PCR	; SIGNIFICAND LENGTH TABLE
	ABX
	LDD	EXPR,U

	CMPD	0,X		; Exponent below upper bound?
	BGE	3F		; No, bail out.

	;
	; IF THE EXPONENT IS BELOW THE LOWER BOUND THEN JUST
	; OR ALL THE FRACTION BYTES INTO THE STIKY BYTE AND
	; ZERO OUT THE FRACTION.
	;
	CMPD	#LOWBND		; Exponent below lower bound?
	BGT	1F		; No, it's in-bounds.

	CLR	STIKY,U		; INITIALIZE STIKY BYTE
	LEAX	RESULT,U
	LBSR	FILSKY		; FILL STICKY
	*
	* NOW UPDATE EXPONENT WITH CORRECT VALUE
	*
	LDB	0,S
	LEAX	SIGSIZ,PCR
	LDD	B,X
	STD	EXPR,U
	LDD	#00
	STD	EXP2,U
	BRA	2F
1
	;
	; ELSE IF THE EXPONENT WITHIN THE UPPER AND LOWER
	; BOUNDS THEN RIGHT SHIFT THE SGNIFICAND WHILE
	; INCREMENTING THE EXPONENT WHILE ADDITIONALLY
	; ORING INTO THE STIKY BYTE THE BITS THAT FALL
	; OFF THE END OF THE STACK FRAME ARGUMENT.
	;
	;
	; NOW UPDATE EXPONENT WITH CORRECT VALUE
	;
	LEAX	SIGSIZ,PCR
	LDB	0,S		; PRECISION INDEX
	LDD	B,X		; MOVE EXPONENT
	STD	EXPR,U

	SUBD	EXP2,U		; CALCULATES # OF SHIFTS TO DO
	CLR	STIKY,U		; INITIALIZE STIKY BYTE
	LEAX	RESULT,U
	LBSR	DENORM		; DENORMALIZE RESULT
2
	;
	; ROUND THAT FRACTIONAL PART OF SIGNIFICAND LIES
	; WITHIN ROUNDING PRECISION
	;
	LEAX	RESULT,U
	LBSR	ROUND
	;
	; NOW NORMALIZE THE RESULT AGAIN
	;
	; IF THE ARGUMENT WAS ORIGINALLY NORMALIZED THEN
	; THEN NORMALIZE AS USUAL
	;
	LDA	FRACT2,U	; LOOK AT ORIGINAL ARGUMENT
	BGE	1F
	; ORIGINALLY NORMALIZED
	LBSR  LNORM
	BRA	3F
1
	;
	; ELSE IF THE ARGUMENT WAS ORIGINALLY UNORMALIZED
	; THEN ONLY SHIFT THE SIGNIFICAND UNTIL IT REFLECTS
	; THE ORIGINAL PRECISION, I.E. EXPONENT SAME AS BEFORE
	;
	LDY	EXP2,U		; USE ORIGINAL EXP. AS REFERENCE
	LBSR	ENORM
3
	LEAS	1,S		; CLEAN UP STACK
4	RTS			; RETURN

*
* SIGNIFICAND SIZE TABLE
*
SIGSIZ	FDB	23
	FDB	52
	FDB	63
	FDB	23
	FDB	52

*
* G-BYTE OFFSET TABLE
*
GOSET	FCB	3		; SINGLE
	FCB	6		; DOUBLE
	FCB	8		; EXTENDED
	FCB	3		; SINGLE (XXXJRT EXT. FORCE TO ...?)
	FCB	6		; EXT. FORCE TO DOUBLE

;*****************************************************************
;
; TTL INTEGER TO FLOATING CONVERSION
;
;*****************************************************************
;
; PROCEDURE FLOAT
;    FLOAT CONVERTS A BINARY INTEGER TO A FLOATING
; REPRESENTATION. THE INPUT ARGUMENT CAN EIHTER BE
; A 16 OR 32 BIT SIGNED INTEGER. IF THE ARGUMENT
; IS 32 BIT LONG AND THE DESTINATION IS SINGLE
; THEN THE VALUE IS ROUNDED ONCE.
;
;  ON ENTRY:
;     U IS A STACK FRAME POINTER
;
;  ON EXIT:
;     RESULT CONTAINS A FLOATING VALUE REPRESENTING
;     THE BINARY INTEGER.
;
FLOAT
	LEAX	RESULT,U
	LDB	#ARGSIZ-1
1	CMPB	#0
	BLT	1F
	CLR	B,X
	DECB
	BRA	1B
1
	;
	; SET EXPONENT TO PROPER VALUE
	;
	LDA	FUNCT,U		; CHECK FUNCTION
	CMPA	#FCFLTS		; Single precision float?
	BNE	1F		; No, must be double.
	LEAY	SINTSZ,PCR
	BRA	2F
1	LEAY	DINTSZ,PCR
2
	;
	; MOVE INTEGER TO RESULT
	;
	LDD	0,Y
	STD	EXPR,U
	LDD	FRACT2,U
	STD	FRACTR,U
	LDD	FRACT2+2,U
	STD	FRACTR+2,U
	;
	; CHECK SIGN OF INTEGER AND NEGATE THE INTEGER
	; IF NECESSARY.
	;
	LDA	FRACTR,U
	BGE	1F		; Skip if sign positive.
	; Sign negative.
	LDA	#$80		; SET SIGN NEGATIVE
	STA	RESULT,U
	LEAX	FRACTR,U
	COM	0,X
	COM	1,X
	COM	2,X
	NEG	3,X
	BCS	1F
	INC	2,X
	BNE	1F
	INC	1,X
	BNE	1F
	INC	0,X
1
	;
	; NORMALIZE RESULT
	;
	LEAX	RESULT,U
	LBSR	SNORM
	;
	; IF THE ARGUMENT WAS 32 BITS LONG AND THE PRECISION
	; IS SINGLE, THEN ROUND THE RESULT TO YIELD EXACT
	; REPRESENTATION
	;
	LDA	FUNCT,U
	CMPA	#FCFLTD		; Double precision float?
	BNE	1F		; No, skip.
	LDA	RPREC,U		; PRECISION RESULT
	CMPA	#SIN		; Single precision?
	BEQ	2F		; Yup, do the rounding.
	CMPA	#EFS		; Ext. force to single?
	BNE	1F		; No, skip rounding.
2
	STA	STIKY,U		; SET STIKY BYTE
	LBSR	ROUND		; ROUND RESULT
1
	RTS			; RETURN