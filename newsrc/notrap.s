;
; TTL  OVERFLOW/UNDERFLOW NO TRAP HANDLERS
; NAM  NOTRAP
;
; LINKING LOADER DEFINITIONS
;
; XDEF	UNFLNT,OVFLNT,MAXTBL,MINTBL
;
; XREF	ROUND,TFRACT,MOVE,INFIN,NAN,ZERO,LARGE
; XREF	FILSKY,DENORM,FPMOVE,DNMTBL
;
; REVISION HISTORY:
;   DATE	PROGRAMMER     REASON
;
;  28.MAY.80	G. STEVENS     ORIGINAL
;  03.AUG.80	G. STEVENS     FIX MIN & MAX TABLES
;  13.AUG.80	G. STEVENS     REWRITE UNFLNT W/ UTILITIES
;  21.AUG.80	G. STEVENS     REWORK NOTRAP AND FIX TYPO
;  22.AUG.80	G. STEVENS     SET INEXACT FLAG IN OVFLNT
;  25.AUG.80	G. STEVENS     USE NEW TABLE IN UNFLNT
;  27.AUG.80	J. BONEY       FIX TYPOS IN OVFLNT
;  05.SEP.80	G. STEVENS     CLEAR ERROVF IN OVFLNT
;  03.OCT.80	G. STEVENS     FIX BITCNT TBL. REF. IN UNFLNT
;  08.DEC.80	J. BONEY       OVFLNT-CHANGED BRA CLROVF TO BSR CLROVF
;  28.JUN.22    @thorpej       Updated for asm6809.  New comments
;                              are in mixed-case.
;

;
; HERE ARE A BUNCH OF COMMONLY USED TABLES
;

;
; MAX EXPONENT TABLE
;
MAXTBL	FDB	SMAXEX		; SINGLE
	FDB	DMAXEX		; DOUBLE
	FDB	EMAXEX		; EXTENDED
	FDB	EMAXEX		; EXT. FORCE TO SINGLE (XXXJRT tbl.s has SMAXEX)
	FDB	EMAXEX		; EXT. FORCE TO DOUBLE (XXXJRT tbl.s has DMAXEX)

;
; MIN EXPONENT TABLE
;
MINTBL	FDB	SMINEX		; SINGLE
	FDB	DMINEX		; DOUBLE
	FDB	EMINEX		; EXTENDED
	FDB	EMINEX		; EXT. FORCE TO SINGLE (XXXJRT tbl.s has SMINEX)
	FDB	EMINEX		; EXT. FORCE TO DOUBLE (XXXJRT tbl.s has DMINEX)

;
; BIT COUNT TABLE ( TELLS HOW MANY BITS
; OF SIGNIFICANCE THERE GIVEN A CERTAIN
; PRECISION )
;
BITCNT	FDB	25		; SINGLE
	FDB	54		; DOUBLE
	FDB	65		; EXTENDED
	FDB	25		; EXT. FORCE TO SINGLE
	FDB	54		; EXT. FORCE TO DOUBLE

;
; HERE ARE THE "NO TRAP" OVERFLOW AND UNDERFLOW
; HANDLERS.
;

;*****************************************************************
;
; SUBROUTINE  UNFLNT
;
;    UNFLNT HANDLES UNDERFLOW WHEN THE UNDERFLOW
; TRAP IS DISABLED.
;
; ON ENTRY: STCK FRAME RESULT CONTAINS INPUT ARGUMENT.
;	    U - POINTER TO THE STACK FRAME
;
; ON EXIT: STACK FAME RESULT CONTAINS A DENORMALIZED
;	   VALUE OR TRUE ZERO.
;	   U,S - UNCHANGED
;	   X,Y,D,CC - DESTROYED
;
; OPERATION:
;	THE RESULT IS DENORMALIZED ROUNDED AND SET TO
; A TRUE ZERO IF NECCESSARY. IF THE ROUNDING MODE IS
; NOT EITHER ROUND TO - INFINITY OR + INFINITY, THEN
; THE UNDERFLOW FLAG IS SET.
;
UNFLNT
	;
	; GET PROPER MIN. EXPONENT
	;
	LEAY	BITCNT,PCR
	LEAX	DNMTBL,PCR	; EXPONENT TABLE
	LDB	RPREC,U		; DETERMONE PRECISION
	ABX			; PTR INTO EXPONENT TABLE
	LEAY	B,Y		; PTR INTO BITCNT TABLE
	;
	; TAKE DIFFERENCE OF MIN. AND ACTUAL
	; EXPONENTS
	;
	LDD	0,X
	SUBD	EXPR,U
	;
	; IF THE EXPONENT DIFFERENCE MEANS THAT THE FRACTION
	; AND THE GUARD BIT WILL BECOME ZERO UPON DENORMALIZING
	; THEN JUST OR THESE BITS INTO THE STIKY AND ZERO THEM OUT.
	;
	LEAX	RESULT,U
	CMPD	0,Y
	BLE	1F
	LBSR	FILSKY		; FILL STIKY
	BRA	2F
1
	; ELSE DENORMALIZE THE FRACTION AS PLANNED
	LBSR	DENORM		; DENORMALIZE THE FRACTION
2
	LBSR	ROUND		; ROUND RESULT
	;
	; IF THE FRACTION BECAME ZERO AS A RESULT OF DENORMALIZING
	; AND ROUNDING, THEN SET THE RESULT TO A TRUE ZERO.
	;
	LBSR	TFRACT
	BNE	1F		; Go handle fraction not zero
	LDD	#$8000		; ZERO EXPONENT
	STD	EXPR,U
	LDA	#TYZERO		; ZERO TYPE
	STA	TYPER,U
	BRA	2F

1	; SET THE PROPER DENORMALIZED EXPONENT
	LEAX	MINTBL,PCR	; MINIMUM EXPONENT TABLE
	LDB	RPREC,U		; PRECISION INDEX
	LDD	B,X		; DENORMALIZED EXPONENT
	STD	EXPR,U
2
	;
	; CHECK ROUNDING MODE; IF NOT RN OR RP THEN CLEAR
	; THE UNDERFLOW FLAG.
	;
	; XXXJRT Huge discrepancy between comments and code
	; here.  Large block comments says "RN OR RP".
	; Inline comments say "NOT RP" and "NOT RM".
	; **CODE** says "IF  A,NE,#RN" and "IF  A,NE,#RZ".
	; NEED TO SORT THIS OUT!  (Just go look at notrap.sa
	; to see the original.)
	;
	LDA	[PFPCB,U]	; CONTROL BYTE IN FPCB
	ANDA	#CTLRND		; ROUND BITS
	CMPA	#RN		; mode == RN? (XXXJRT "RP")
	BRA	1F		; Yes, skip.
	CMPA	#RZ		; mode == RZ? (XXXJRT "RM")
	BRA	1F
	LDA	TSTAT,U
	ANDA	#$FF-ERRUNF	; CLEAR UNDERFLOW FLAG
	STA	TSTAT,U
1
	RTS

;*****************************************************************
;
; SUBROUTINE  OVFLNT
;
;   OVFLNT HANDLES THE OVERFLOW WHEN THE OVERFLOW
; TRAP IS DISABLED.
;
; ON ENTRY: STACK FRAME RESULT CONTAINS THE INPUT
;	    ARGUMENT
;
; ON EXIT: U,S - UNCHANGED
;	   X,Y,D,CC - DESTROYED
;
OVFLNT
	LDA	TSTAT,U
	ORA	#ERRINX		; SET INEXACT RESULT BIT
	STA	TSTAT,U
	;
	; CASE( ROUNDING MODE ) TO DETERMINE ACTION
	; TO BE TAKEN.
	;
	; Similar restructuring here as the changes
	; made to ROUND.  --thorpej
	;
	LDA	[PFPCB,U]	; CONTROL WORD
	ANDA	#CTLRND		; ROUNDING BITS

	CMPA	#RN		; Round-to-nearest?
	BEQ	OVFLNT_rn
	CMPA	#RZ		; Round-to-zero?
	BEQ	OVFLNT_rz
	CMPA	#RP		; Round-to-plus-infinity?
	BEQ	OVFLNT_rp

	; Default case is Round-to-minus-infinty.
	BSR	CLROVF		; CLEAR OVERFLOW FLAG

	LDA	RESULT,U
	BLT	1F		; Go handle negative result.

	LDA	FRACTR,U
	;
	; IF RESULT IS POSITIVE AND NORMALIZED
	; THEN DELIVER LARGEST POSSIBLE NUMBER
	; TO DESTINATION.
	;
	BGE	2F		; Go handle not-normalized result.
	LEAX	LARGE,PCR	; LARGE CONSTANT
	BSR	MVRES		; MOVE TO RESULT
	BRA	OVFLNT_done	; Done.

2	;
	; ELSE IF RESULT POSITIVE AND NOT NORMALIZED
	; THEN DELIVER SIGNIFICAND AND LARGEST
	; EXPONENT TO DESTINATION.
	;
	BSR	SETEXP		; SET LARGEST EXPONENT
	BRA	OVFLNT_done	; Done.

1	; RESULT IS NEGATIVE 
	LEAX	INFIN,PCR	; INFINITY CONSTANT
	BSR	MVNRES		; MOVE TO RESULT AND NEGATE
	BRA	OVFLNT_done	; Done.

	; Round-to-plus-infinity
OVFLNT_rp
	BSR	CLROVF		; CLEAR OVERFLOW FLAG

	LDA	RESULT,U
	BGE	1F		; Go handle positive result.

	LDA	FRACTR,U
	;
	; IF THE RESULT IS NEGATIVE AND NORMALIZED
	; THEN DELIVER LARGEST NEGATIVE NUMBER TO
	; DESTINATION.
	;
	BGE	2F		; Go handle not-normalized case.
	LEAX	LARGE,PCR	; LARGE CONSTANT
	BSR	MVNRES		; MOVE TO RESULT AND SET NEGATIVE
2
	;
	; ELSE IF RESULT IS NEGATIVE AND NOT NORMALIZED
	; THEN DELIVER SIGNIFICAND AND LARGEST EXPONENT
	; TO DESTINATION.  (This also applies to normalized.)
	;
	BSR	SETEXP		; SET EXPONENT GIVEN THE PRECISION
	BRA	OVFLNT_done	; Done.

1	; RESULT IS POSITIVE
	LEAX	INFIN,PCR	; INFINITY CONSTANT
	BSR	MVRES		; MOVE TO RESULT
	BRA	OVFLNT_done

	; Round-to-zero and Round-to-nearest cases are the same.
OVFLNT_rz
OVFLNT_rn
	;
	; RETURN INFINITY FO PROPER SIGN
	;
	LEAX	INFIN+1,PCR	; INFINITY CONSTANT
	LEAY	EXPR,U		; DESTINATION
	LDB	#ARGSIZ-1
	LBSR	MOVE
	; FALLTHROUGH to OVFLNT_done

OVFLNT_done
	RTS

;
;  PROCEDURE CLROVF
;
;      CLEARS THE OVERFLOW FLAG IN TSTAT
;
CLROVF
	LDA	TSTAT,U		; CLEAR OVERFLOW FLAG
	ANDA	#$FF-ERROVF
	STA	TSTAT,U
	RTS			; RETURN

;
;  PROCEDURE  SETEXP
;
;	INSERTS LARGEST EXPONENT INTO THE EXPONENT FIELD OF THE RESULT
;
SETEXP
	LDB	RPREC,U 	; DETERMINE PRECISION
	LEAX	MAXTBL,PCR	; EXPONENT TABLE
	LDD	B,X
	SUBD	#01
	STD	EXPR,U
	RTS			; RETURN

;
;   PROCEDURE  MVRES
;
;      MOVES THE STACK FRAME ARGUMENT POINTED AT BY THE X-REG. TO
;   THE STACK FRAME RESULT
;
MVRES
	LEAY	RESULT,U	; DESTINATION
	LBSR	FPMOVE
	RTS			; RETURN

;
;   PROCEDURE  MVNRES
;
;      MOVES THE STACK FRAME ARGUMENT POINTED AT BY THE X-REG. TO
;   THE STACK FRAME RESULT AND MAKES THE RESULT NEGATIVE
;
MVNRES
	LEAY	RESULT,U	; DESTINATION
	LBSR	FPMOVE
	LDA	#$80
	STA	SIGNR,U
	RTS			; RETURN
