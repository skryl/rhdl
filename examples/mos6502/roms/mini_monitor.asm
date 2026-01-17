; Mini Apple II Monitor ROM - Compact Version
; Simple monitor with keyboard echo
;
; Memory Map:
;   $0400-$07FF - Text page 1
;   $C000       - Keyboard data (bit 7 = strobe)
;   $C010       - Clear keyboard strobe
;   $F800-$FFFF - ROM

; Zero page
CH       = $24
CV       = $25
BASL     = $28
BASH     = $29

; I/O
KBD      = $C000
KBDSTRB  = $C010

         .ORG $F800

; =====================================================
; RESET
; =====================================================
RESET:
         CLD
         LDX #$FF
         TXS

         ; Clear screen
         LDA #$00
         STA BASL
         LDA #$04
         STA BASH
         LDY #0
         LDA #$A0
CLRLP:   STA (BASL),Y
         INY
         BNE CLRLP
         INC BASH
         LDA BASH
         CMP #$08
         BCC CLRLP-2

         ; Init cursor
         LDA #0
         STA CH
         STA CV

         ; Calculate line address
         JSR VTAB

         ; Print message
         LDX #0
PRMSG:   LDA MSG,X
         BEQ MAIN
         ORA #$80
         JSR COUT
         INX
         BNE PRMSG

; =====================================================
; MAIN - Echo keyboard to screen
; =====================================================
MAIN:
         ; Wait for key
         LDA KBD
         BPL MAIN
         STA KBDSTRB
         ORA #$80

         ; Handle return
         CMP #$8D
         BEQ DOCR

         ; Echo character
         JSR COUT
         JMP MAIN

DOCR:    LDA #0
         STA CH
         INC CV
         LDA CV
         CMP #24
         BCC DOCR2
         LDA #0
         STA CV
DOCR2:   JSR VTAB
         JMP MAIN

; =====================================================
; VTAB - Set BASL/BASH for row CV
; =====================================================
VTAB:
         LDA CV
         AND #$07
         ASL A
         TAX
         LDA LTBL,X
         STA BASL
         LDA LTBL+1,X
         STA BASH
         LDA CV
         CMP #8
         BCC VTDN
         CMP #16
         BCC VT8
         INC BASH
         JMP VTDN
VT8:     CLC
         LDA BASL
         ADC #$80
         STA BASL
         BCC VTDN
         INC BASH
VTDN:    RTS

LTBL:    .WORD $0400, $0480, $0500, $0580
         .WORD $0600, $0680, $0700, $0780

; =====================================================
; COUT - Output character in A
; =====================================================
COUT:
         PHA
         LDY CH
         STA (BASL),Y
         INC CH
         LDA CH
         CMP #40
         BCC COUTDN
         LDA #0
         STA CH
         INC CV
         LDA CV
         CMP #24
         BCC COUT2
         LDA #0
         STA CV
COUT2:   JSR VTAB
COUTDN:  PLA
         RTS

; =====================================================
; Message
; =====================================================
MSG:     .BYTE $0D
         .BYTE "APPLE ][ MINI MONITOR", $0D
         .BYTE "TYPE TO ECHO, RETURN FOR NEWLINE", $0D
         .BYTE 0

; =====================================================
; Vectors
; =====================================================
         .ORG $FFFA
         .WORD RESET
         .WORD RESET
         .WORD RESET

         .END
