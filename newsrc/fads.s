;
;  NAM	FADS
;  TTL FLOATING-POINT ADD ROUTINE
;
; LINKNG LOADER DEFINITIONS
;
; XREF	TFRACT,VALID,FRCTAB,BITTBL,DNORM1,NORMQK
; XREF	FPMOVE,XADDY,CLRES,COMP2,DENORM
;
; XDEF	FADD,FSUB
;
;
;    REVISION HISTORY:
;      DATE	     PROGRAMMER 	      REASON
;
;    23.MAY.80	     G.WALKER		      ORIGINAL
;    16.JUN.80	     G. STEVENS 	      FIX FSUB
;     1.JUL.80	     G.WALKER		      CODE COMPACTION
;    13.JUL.80	     G.WALKER		      SPEED & SHRINK
;    17.JUL.80	     G.WALKER		      REWRITE TO CORRECT
;						HANDLING OF UN-NORM.
;    22.JUL.80	     G.WALKER		      INCLUDE STICKY IN COMPL.
;    06.AUG.80	     G.WALKER		      OR BITS OF RESULT INTO
;						STICKY BYTE
;    13.AUG.80	     G.WALKER		      SAVE BYTES USING "DENORM"
;    18.AUG.80	     G. STEVENS 	      SAVE MORE BYTES W/ "DENORM"
;    07.OCT.80	     G.WALKER		      CORRECT LARGER ARG MOVE
;    28.JUN.22       @thorpej                 Updated for asm6809.  New
;                                             comments are in mixed-case.
;
;*****************************************************************
;
;    FADD --
;	 ADDS TWO ARGUMENTS FROM THE STACK FRAME
;    AND LEAVES THE RESULT IN THE STACK FRAME. THE
;    EXPONENT OF THE RESULT IS THE LARGEST OF THE
;    TWO EXPONENTS.  THE ARGUMENT WITH THE SMALLER
;    EXPONENT IS DENORMALIZED UNTIL THE TWO EXPONENTS
;    ARE EQUAL.  BITS SHIFTED OUT TO THE RIGHT ARE OR'ED
;    INTO THE STICKY BYTE.
;	 IF THE DIFFERENCE IN EXPONENTS EXCEEDS ROUNDING
;    PRECISION + GUARD BIT, THEN RESULT IS ARGUMENT
;    WITH THE LARGEST EXPONENT,  ELSE THE ARGUMENT WITH
;    THE SMALLEST FRACTION IS COMPLEMENTED AND THE TWO
;    FRACTIONS ARE ADDED.  THE RESULT IS TESTED FOR ZERO
;    DUE TO CANCELLATION AND NORMALIZED IF ONE OF THE
;    INPUT ARGUMENTS WAS NORMALIZED.
;
;    ALGORITHM IS:
;
;    IF EXP1 > EXP2 THEN
;	 EXPR=EXP1; SMALLER=ARG2;
;    ELSE
;	 EXPR=EXP2; SMALLER=ARG1;
;    ENDIF
;    GET ABSOLUTE DIFFERENCE IN EXPONENTS;
;    IF DIFFERENCE > PRECISION THEN
;	RETURN LARGER ARGUMENT;
;    ELSE
;      DENORMALIZE SMALLER, THROWING BITS TO THE RIGHT
;	 INTO THE STICKY BUCKET;
;      REMEMBER IF ONE ARGUMENT IS NOW NORMALIZED;
;      IF SIGN1 <> SIGN2 THEN
;	 IF FRACT1 < FRACT2 THEN
;	   2'S COMPL. FRACT1;  SIGNR=SIGN2
;	 ELSE
;	   2'S COMPL. FRACT2; SIGNR=SIGN1
;	 ENDIF
;      ENDIF   SIGNS ARE NOT EQUAL
;      ADD THE FRACTIONS INTO THE RESULT
;    ENDIF
;
;    IF THE V-BIT IS SET THEN
;	SHIFT RESULT FRACTION RIGHT ONE BIT AND INCREMENT
;	RESULT EXPONENT;
;    ENDIF
;    IF FRACTR = 0 THEN
;      IF ONE ARGUMENT WAS NORMALIZED
;	 RETURN SIGNED NORMAL ZERO
;      ELSE
;	 RETURN SIGNED UN-NORMALIZED ZERO
;      ENDIF
;    ELSE	 FRACTR <> 0
;      IF ONE ARGUMENT WAS NORMALIZED
;	 NORMALIZE RESULT
;      ENDIF
;    ENDIF
;    CHECK FOR UNDERFLOW;
;    ROUND RESULT TO PROPER PRECISION;
;    CHECK FOR OVERFLOW.
;
;    LOCAL STORAGE USED:  (STACK DISPLACEMENT)
;	FRCNDX (1) -- LARGEST INDEX OF BYTES IN FRACT.
;	FRBITS (2) -- TWO BYTE COUNT OF SIGNIFICANT BITS +
;		     GUARD BIT IN THE FRACTION
;	EXPDIF (2) -- (2 BYTES) DIFFERENCE IN EXPONENTS
;	ADUNRM (1) -- MSBIT IS 0 IF BOTH ARGUMENTS WERE
;		      UNNORMALIZED AFTER DENORMALIZATION
;		      OF SMALLER ARGUMENT
;	TMPX   (2) -- TEMP. SAVE FOR X-REGISTER
;	DIDCMP (1) -- =0 IF NO COMPLEMENT, =1 IF A COMPLEMENT
;		      WAS PERFORMED.
;
FRCNDX	SET	0
FRBITS	SET	1
EXPDIF	SET	3
ADUNRM	SET	5
TMPX	SET	6
DIDCMP	SET	8

FADD
	LEAS	-9,S		; RESERVE LOCAL STORAGE
	LDA	RPREC,U
	LSRA
	LEAX	FRCTAB,PCR
	LDB	A,X		; GET # BYTES FOR THIS PRECISION
	DECB			; CHANGE TO LARGEST INDEX
	STB	FRCNDX,S
	LEAX	BITTBL,PCR
	LDB	A,X
	SEX			; EXTEND TO 16 BIT
	STD	FRBITS,S	; SAVE # OF FRACTION BITS
	CLR	DIDCMP,S	; DEFAULT TO NO COMPL.
	;
	; FIND WHICH ARGUMENT IS SMALLER
	;
	LDX	EXP1,U
	CMPX	EXP2,U
	BLE	1F
	LEAX	ARG1,U		; X POINTS TO ARG WITH LARGER EXP
	LEAY	ARG2,U		; Y POINTS TO ARG WITH SMALLER EXP
	BRA	2F
1
	LEAX	ARG2,U		; X POINTS TO ARG WITH LARGER EXP
	LEAY	ARG1,U		; Y POINTS TO ARG WITH SMALLER EXP
2

	;
	; CREATE ABSOLUTE DIFFERENCE IN EXPONENTS.
	;
	LDD	EXP,X		; SUBTRACT SMALLER EXP FROM LARGER
	SUBD	EXP,Y
	STD	EXPDIF,S	; SAVE DIFFERENCE IN EXPS
	LEAX	FRACT,X		; POINT TO FRACTION PART
	LEAY	FRACT,Y
	;
	; IF THE DIFFERENCE IN EXPONENTS IS LARGER THAN THE
	; NUMBER OF SIGNIFICANT BITS IN THIS PRECISION, THEN
	; 'OR' THE  FRACTION OF THE SMALLER ARGUMENT INTO
	; THE STIKY BYTE AND MOVE LARGER FRACTION TO THE RESULT.
	;

	CMPD	FRBITS,S	; UNLESS FRACTIONS OVERLAP
	BLE	FADD_overlap_else

	LDA	0,X		; TEST NORMALIZATION OF LARGER ARG
	ANDA	#$80		; (SMALLER IS DENORMED)
	STA	ADUNRM,S
	LDA	FRCNDX,S
	CLRB			; INITIAL STICKY BYTE IS ZERO

1	CMPA	#0
	BLT	1F
	ORB	A,Y		; 'OR' SMALLER FRACTION
	DECA			; INTO STICKY BYTE
	BRA	1B
1
	STB	STIKY,U		; SAVE NEW STIKY BYTE
	LEAX	-FRACT,X	; POINT TO ENTIRE FP NUMBER FOR MOVE
				; LARGER ARG WILL BE COPIED TO RSLT
	BRA	FADD_overlap_endif
FADD_overlap_else
	;
	; ELSE DENORMALIZE SMALLER AND SHIFT ONE BITS
	; OUT OF THE RIGHT INTO THE STICKY BYTE.
	;
	PSHS	X		; SAVE XREG
	LEAX	-FRACT,Y	; POINT TO SMALLER NUMBER
	LBSR	DENORM		; DENORM IT BASE ON COUNT IN 'B'
	PULS	X		; RESTORE X-REG
	;
	; TEST NORMALIZATION OF FRACTIONS: 'ADUNRM'
	; IS =1 IF ONE WAS NORMALIZED, =0 IF BOTH
	; UNNORMALIZED.
	;
	LDA	0,X
	ORA	0,Y		; STORE WHETHER EITHER FRACTION
	ANDA	#$80		; MASK TO MSBIT
	STA	ADUNRM,S	; IS NORMALIZED
	;
	; IF ARGS DIFFER IN SIGN, THEN COMPLEMENT
	; THE SMALLER ARG'S FRACTION
	;
	LDA	ARG1,U
	CMPA	ARG2,U		; UNLESS SIGNS THE SAME
	BEQ	FADD_signs_endif

	;
	; COMPARE SIZES OF FRACTIONS.
	;
	LDA	#1
	STA	DIDCMP,S	; SAVE THAT COMPLEMENT WAS DONE
	STX	TMPX,S		; TEMP. SAVE X-REG FOR COMPL.
	CLRA			; BYTE INDEX
	LDB	A,X

1	CMPB	A,Y		; LOOP TO COMPARE BYTES
	BNE	1F
	CMPA	FRCNDX,S	; IF ALL BYTES ARE COMPARED,
	BGE	FADSMY		; THEN FRACTS ARE EQUAL
	INCA
	LDB	A,X
	BRA	1B
1
	; IF BYTES NOT EQUAL, THEN BRANCH ON CC-REG.
	BHI	FADSMY		; Y POINTS TO SMALLER FRACT

FADSMX		; FRACT,X IS SMALLER
	LDA	-FRACT,Y	; GET SIGN OF LARGER FRACT IN A
	STA	-FRACT,X	; RESULT SIGN INTO ARG WITH LARGER EXP
				; (WILL ULTIMATELY BE MOVED TO RESULT)
	BRA	DOCMPL		; COMPLEMENT FRACT POINTED TO BY X-REG
	;
	; NOW COMPLEMENT THE SMALLER FRACTION.
	;
FADSMY		; Y-POINTS TO SMALLER FRACTION
	LEAX  0,Y		; POINT X TO SMALLER FRACTION

DOCMPL
	LDB	FRCNDX,S	; B CONTAINS LARGEST INDEX INTO FRACTION
	CMPX	TMPX,S		; IF FRACTION TO BE COMPLEMENTED
	BNE	1F
	LBSR	COMP2		; WAS NOT DENORMALIZED--2'S COMPL.
	BRA	3F
1	; ELSE STIKY BYTE IS PART OF FRACTION
	TST	STIKY,U		; IF ZERO STIKY, DO 2'S COMP
	BNE	2F
	LBSR	COMP2
	BRA	3F
2
	CMPB	#0
	BLT	3F
	COM	B,X
	DECB
	BRA	2B
3
	LDX	TMPX,S		; RESTORE POINTER TO ARG WITH SMLR EXP
FADD_signs_endif
	;
	; ADD TWO FRACTIONS INTO RESULT
	;
	LBSR	XADDY		; ADD FRACTIONS
	LEAX	-FRACT,X	; POINT TO ENTIRE FP NUMBER
	BCC	1F		; IF WAS CARRY OUT FROM ADD
	TST	DIDCMP,S	; AND WAS NOT COMPLEMENTED
	BNE	1F
	LBSR	DNORM1		; ADJUST FOR OVERFLOW
1
FADD_overlap_endif
	LEAY	RESULT,U
	LBSR	FPMOVE		; MOVE FP NUMBER TO RESULT
	LEAX	RESULT,U	; POINT X TO RESULT
	LBSR	TFRACT

	BNE	FADD_frac_else	; IF FRACTION IS ZERO
	TST	ADUNRM,S	; IF ONE ARG NORMALIZED
	BGE	1F
	LDD	#ZEROEX		; SET EXPONENT FOR NORMAL ZERO
	STD	EXPR,U
1
	LDY	PFPCB,U
	LDA	CTL,Y
	ANDA	#CTLRND		; CHECK ROUNDING MODE

	CMPA	#RM		; IF ROUND TO -INFINITY
	BNE	1F
	LDA	#$80
	STA	RESULT,U	; SET RESULT TO -0
	BRA	2F
1
	; XXXJRT save an instruction by doing "CLR RESULT,U"?
	CLRA			; IF ROUND TO +INFINITY
	STA	RESULT,U	; SET RESULT TO +0
2
	BRA	FADD_frac_endif

FADD_frac_else	; FRACTION IS NON-ZERO
	TST	ADUNRM,S	; IF ONE ARG NORMALIZED
	BGE	1F
	LBSR	NORMQK		; NORMALIZE RESULT
1
	;
	; THE LOW ORDER BYTES OF THE RESULT ARE
	; OR'ED INTO THE STIKY BYTE. THE 'ROUND' ROUTINE
	; WILL 'OR' THE BITS IN THE SAME BYTE AS THE GUARD BIT
	; INTO THE STICKY BYTE.
	;
	LDB	#0
	LBSR	DENORM

FADD_frac_endif
	;
	; FINISH PROCESSING WITH CHECKS
	; FOR EXCEPTIONAL CONDITIONS
	;
	LBSR	VALID		; CHECK FOR VALID RESULT
	LEAS	9,S		; REMOVE LOCAL STORAGE
	RTS

; TTL  FLOATING-POINT SUBTRACT
;***********************************************************
;
;    FSUB --
;	SUBTRACTS ARG2 FROM ARG1, LEAVING DIFFERENCE IN RESULT,
;    BY NEGATING ARG2 AND CALLING 'FADD'.
;
FSUB
	LDA	ARG2,U
	COMA
	ANDA	#$80		; NEGATE ARG2
	STA	ARG2,U		; RESTORE SIGN
	LBRA	FADD		; AND ADD
