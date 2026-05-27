Nesori_ZP = $00
Nesori_BSS = $200

; =========================================================================================
;
; Nesori music data format:
;
;     $00-$7F = note (high 4 bits for octave, lower 4 bits for note) and terminate reading ($7F means note release)
;
;     $80     = set volume duty envelope ptr (2 bytes ptr followed)
;     $81     = set pitch envelope ptr (2 bytes ptr followed)
;
;     $AD     = jump to ptr (2 bytes ptr followed)
;     $AE     = call ptr (2 bytes ptr followed)
;     $AF     = return from this sequence if this was called, otherwise stop this channel entirely.

;     $B0-$BF = set volume
;     $C0-$FF = set delay
;
; Nesori volume duty envelope data format:
;
;     starts with two bytes which are release rate, release decreasement byte, which will basically-
;     decreasement current channel's volume by <release decreasement> every <release rate> ticks.
;
;     the start volume is determined from the last volume value when the note was released.
;
;     after these two bytes, literal values for register $4000/$4004/$4008/$400C immediately follows.
;     but when bit 5 becomes clear, then the pointer will go back to the previous byte, marking-
;     envelope end point.
;
;     it works exactly the same with triangle. but in noise, the bit for indicating loop point is bit 7 instead of 5
;
; Nesori pitch envelope data format:
;
;     simply lists 2's complement values of pitch offset that will be added on final period register.
;     however value $80 indicates envelope loop point. one byte offset follows
;
; =========================================================================================

enum Nesori_ZP
		Nesori_temp_ptr: .dsb 2
		Nesori_temp_ptr2: .dsb 2
ende

enum Nesori_BSS
		Nesori_tempo: .dsb 1
		Nesori_tempoDec: .dsb 2
		Nesori_tempoAcc: .dsb 2
		Nesori_tempoCnt: .dsb 2
		Nesori_tempoRem: .dsb 1

		Nesori_chPtrL: .dsb 4
		Nesori_chPtrH: .dsb 4
		Nesori_chDefaultLen: .dsb 4
		Nesori_chLen: .dsb 4
		Nesori_chVol: .dsb 4
		Nesori_chPitch: .dsb 4
		
		Nesori_chBaseNote: .dsb 4
		Nesori_chArpNote1: .dsb 4 ; switches between only this if arp note 2 is 0 (empty)
		Nesori_chArpNote2: .dsb 4
		
		Nesori_chCallStack1PtrL: .dsb 4
		Nesori_chCallStack1PtrH: .dsb 4
		Nesori_chCallStack2PtrL: .dsb 4
		Nesori_chCallStack2PtrH: .dsb 4
		
		Nesori_chVolDutyEnvPtrL: .dsb 4
		Nesori_chVolDutyEnvPtrH: .dsb 4
		Nesori_chVolDutyEnvIndex: .dsb 4
		
		Nesori_chPitchEnvPtrL: .dsb 4 ; base ptr
		Nesori_chPitchEnvPtrH: .dsb 4
		Nesori_chPitchEnvIndex: .dsb 4
		
		Nesori_chReleasing: .dsb 4 ; $00 = play envelope, $FF, release
		
		Nesori_oldHighPeriodReg: .dsb 2
ende

; =========================================================================================

Nesori_dummy_volduty_env: .BYTE 1, $FF, $3F, $00, 2
Nesori_dummy_pitch_env: .BYTE $00, $80, 0

; =========================================================================================

Nesori_play_song: ; A = song number
		ASL
		TAX
		LDA Nesori_track_ptr+0,X
		STA Nesori_temp_ptr+0
		LDA Nesori_track_ptr+1,X
		STA Nesori_temp_ptr+1
		
		LDY #0
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_tempo
		
		LDX #0
@Nesori_chloop:
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPtrL,X
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPtrH,X
		
		LDA #0
		STA Nesori_chPitch,X
		STA Nesori_chArpNote1,X
		STA Nesori_chArpNote2,X
		STA Nesori_chCallStack1PtrH,X
		STA Nesori_chCallStack2PtrH,X
		STA Nesori_chPitchEnvIndex,X
		STA Nesori_chReleasing,X
		
		LDA #1
		STA Nesori_chLen,X
		
		LDA #2
		STA Nesori_chVolDutyEnvIndex,X
		
		LDA #$F0
		STA Nesori_chVol,X
		
		LDA #<Nesori_dummy_volduty_env
		STA Nesori_chVolDutyEnvPtrL,X
		LDA #>Nesori_dummy_volduty_env
		STA Nesori_chVolDutyEnvPtrH,X
		LDA #<Nesori_dummy_pitch_env
		STA Nesori_chPitchEnvPtrL,X
		LDA #>Nesori_dummy_pitch_env
		STA Nesori_chPitchEnvPtrH,X

		INX
		CPX #4
		BNE @Nesori_chloop
		
		LDA #<3600
		STA Nesori_tempoDec+0
		LDA #>3600
		STA Nesori_tempoDec+1
		JMP Nesori_calculateSpeed
		
; =========================================================================================
		
Nesori_calculateSpeed:
		STX Nesori_temp_ptr2+0 ; save X

		LDA Nesori_tempo
		STA Nesori_tempoCnt+0
		ASL
		ROL Nesori_tempoCnt+1
		CLC
		ADC Nesori_tempoCnt+0
		STA Nesori_tempoCnt+0
		LDA Nesori_tempoCnt+1
		AND #1
		ADC #0
		ASL Nesori_tempoCnt+0
		ROL
		ASL Nesori_tempoCnt+0
		ROL
		ASL Nesori_tempoCnt+0
		ROL
		STA Nesori_tempoCnt+1

		LDX #16
		LDA #0
		STA Nesori_tempoAcc+0
		STA Nesori_tempoAcc+1
@divloop:
		ASL Nesori_tempoCnt+0
		ROL Nesori_tempoCnt+1
		ROL
		CMP #3
		BCC @skip
		SBC #3 ; carry is set
		INC Nesori_tempoCnt+0
@skip:
		DEX
		BNE @divloop
		STA Nesori_tempoRem

		LDX Nesori_temp_ptr2+0 ; restore X
		RTS
		
; =========================================================================================

Nesori_update:
		LDA Nesori_tempoAcc+1
		BMI @do_seq_update
		ORA Nesori_tempoAcc+0
		BNE @no_seq_update
@do_seq_update:
		LDX #3
@loop:
		DEC Nesori_chLen,X
		BNE @no_chvar_update
		JSR Nesori_read_sequence
		LDA Nesori_chDefaultLen,X
		STA Nesori_chLen,X
@no_chvar_update:
		DEX
		BPL @loop

		LDA Nesori_tempoAcc+0
		CLC
		ADC Nesori_tempoDec+0
		STA Nesori_temp_ptr+0
		LDA Nesori_tempoAcc+1
		ADC Nesori_tempoDec+1
		STA Nesori_temp_ptr+1

		LDA Nesori_temp_ptr+0
		SEC
		SBC Nesori_tempoRem
		STA Nesori_tempoAcc+0
		LDA Nesori_temp_ptr+1
		SBC #0
		STA Nesori_tempoAcc+1

@no_seq_update:
		LDA Nesori_tempoAcc+0
		SEC
		SBC Nesori_tempoCnt+0
		STA Nesori_tempoAcc+0
		LDA Nesori_tempoAcc+1
		SBC Nesori_tempoCnt+1
		STA Nesori_tempoAcc+1
		
		LDX #0
		JSR Nesori_updatePulse
		INX
		JSR Nesori_updatePulse
		RTS
		
; =========================================================================================

Nesori_read_sequence:
		LDA Nesori_chPtrL,X
		STA Nesori_temp_ptr+0
		LDA Nesori_chPtrH,X
		STA Nesori_temp_ptr+1
		
		LDY #0
Nesori_readloop:
		LDA (Nesori_temp_ptr),Y
		BMI @commands
		BEQ @releasenote
		INY
		STA Nesori_chBaseNote,X
		LDA #2
		STA Nesori_chVolDutyEnvIndex
		LDA #0
		STA Nesori_chPitchEnvIndex
@done: ; save ptr and terminate this subroutine
		TYA
		CLC
		ADC Nesori_temp_ptr+0
		STA Nesori_chPtrL,X
		BCS @hinc
		RTS
@hinc:
		INC Nesori_chPtrH,X
		RTS
		
@releasenote:
		INY
		LDA #$FF
		STA Nesori_chReleasing,X
		BNE @done ; always
		
@delay:
		AND #$1F
		ADC #1-1 ; carry is set
		STA Nesori_chDefaultLen,X
		STA Nesori_chLen,X
		BPL Nesori_readloop ; always
		
@volume:
		AND #$0F
		ASL
		ASL
		ASL
		ASL
		STA Nesori_chVol,X
		BCC Nesori_readloop ; always
		
@commands:
		INY
		CMP #$C0
		BCS @delay
		CMP #$B0
		BCS @volume
		
		STY Nesori_temp_ptr2+0 ; save Y
		TAY
		LDA @commandptrtbl_msb-128,Y
		STA Nesori_temp_ptr2+1
		LDA @commandptrtbl_lsb-128,Y
		LDY Nesori_temp_ptr2+0 ; restore Y
		STA Nesori_temp_ptr2+0
		JMP (Nesori_temp_ptr2)
		
@commandptrtbl_lsb:
		.DL Nesori_cmd_setvolenv,	Nesori_cmd_setpitchenv,	Nesori_cmd_setvol,		$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DL $FFFF,					Nesori_cmd_jump,		Nesori_cmd_call,		Nesori_cmd_return
		
@commandptrtbl_msb:
		.DH Nesori_cmd_setvolenv,	Nesori_cmd_setpitchenv,	Nesori_cmd_setvol,		$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					$FFFF,					$FFFF,					$FFFF
		.DH $FFFF,					Nesori_cmd_jump,		Nesori_cmd_call,		Nesori_cmd_return
		
; =========================================================================================

Nesori_readdone = Nesori_readloop+2+2+2+1+3 ; stupid assembler

Nesori_cmd_setvolenv:
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chVolDutyEnvPtrL,X
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chVolDutyEnvPtrH,X
		LDA #2 ; 2 because first two bytes are header
		STA Nesori_chVolDutyEnvIndex,X
		JMP Nesori_readloop
		
Nesori_cmd_setpitchenv:
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPitchEnvPtrL,X
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPitchEnvPtrH,X
		LDA #0
		STA Nesori_chPitchEnvIndex,X
		JMP Nesori_readloop
		
Nesori_cmd_setvol:
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chVol,X
		JMP Nesori_readloop
		
Nesori_cmd_jump:
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPtrL,X
		LDA (Nesori_temp_ptr),Y
		STA Nesori_chPtrH,X

		LDY #0
		JMP Nesori_readloop
		
Nesori_cmd_call:
		LDA Nesori_chCallStack2PtrH,X
		BNE @stackisfull
		
		LDA (Nesori_temp_ptr),Y
		INY
		STA Nesori_chPtrL,X
		LDA (Nesori_temp_ptr),Y
		INY ; so saving to stack correctly points next command
		STA Nesori_chPtrH,X

		LDA Nesori_chCallStack1PtrH,X
		BNE @secondstack
		
		TYA
		CLC
		ADC Nesori_temp_ptr+0
		STA Nesori_chCallStack1PtrL,X
		LDA Nesori_temp_ptr+1
		ADC #0
		STA Nesori_chCallStack1PtrH,X
		
		LDA Nesori_chPtrL,X
		STA Nesori_temp_ptr+0
		LDA Nesori_chPtrH,X
		STA Nesori_temp_ptr+1

		LDY #0
		JMP Nesori_readloop
		
@secondstack:
		TYA
		CLC
		ADC Nesori_temp_ptr+0
		STA Nesori_chCallStack2PtrL,X
		LDA Nesori_temp_ptr+1
		ADC #0
		STA Nesori_chCallStack2PtrH,X
		
		LDA Nesori_chPtrL,X
		STA Nesori_temp_ptr+0
		LDA Nesori_chPtrH,X
		STA Nesori_temp_ptr+1

		LDY #0
		JMP Nesori_readloop

@stackisfull:
		.BYTE $02 ; kill CPU, blame composer
		
Nesori_cmd_return:
		LDA Nesori_chCallStack2PtrH,X
		BNE @returnfromsecondstack
		LDA Nesori_chCallStack1PtrH,X
		BNE @returnfromfirststack
		DEY ; move pointer to point this return address again. so it stucks in an infinite loop thus sequence end :P
		JMP Nesori_readdone
		
@returnfromfirststack:
		STA Nesori_chPtrH,X
		STA Nesori_temp_ptr+1
		LDA Nesori_chCallStack1PtrL,X
		STA Nesori_chPtrL,X
		STA Nesori_temp_ptr+0
		LDA #0
		STA Nesori_chCallStack1PtrH,X

		TAY
		JMP Nesori_readloop
		
@returnfromsecondstack:
		STA Nesori_chPtrH,X
		STA Nesori_temp_ptr+1
		LDA Nesori_chCallStack2PtrL,X
		STA Nesori_chPtrL,X
		STA Nesori_temp_ptr+0
		LDA #0
		STA Nesori_chCallStack2PtrH,X

		TAY
		JMP Nesori_readloop
		
; =========================================================================================

Nesori_periodTableLsb: .DL $6AD, $64D, $5F3, $59D, $54D, $500, $4B8, $474, $434, $3F8, $3BF, $389
Nesori_periodTableMsb: .DH $6AD, $64D, $5F3, $59D, $54D, $500, $4B8, $474, $434, $3F8, $3BF, $389

Nesori_volTbl:     
		.BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
		.BYTE   0,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1
		.BYTE   0,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  2
		.BYTE   0,  1,  1,  1,  1,  1,  1,  1,  1,  1,  2,  2,  2,  2,  2,  3
		.BYTE   0,  1,  1,  1,  1,  1,  1,  1,  2,  2,  2,  2,  3,  3,  3,  4
		.BYTE   0,  1,  1,  1,  1,  1,  2,  2,  2,  3,  3,  3,  4,  4,  4,  5
		.BYTE   0,  1,  1,  1,  1,  2,  2,  2,  3,  3,  4,  4,  4,  5,  5,  6
		.BYTE   0,  1,  1,  1,  1,  2,  2,  3,  3,  4,  4,  5,  5,  6,  6,  7
		.BYTE   0,  1,  1,  1,  2,  2,  3,  3,  4,  4,  5,  5,  6,  6,  7,  8
		.BYTE   0,  1,  1,  1,  2,  3,  3,  4,  4,  5,  6,  6,  7,  7,  8,  9
		.BYTE   0,  1,  1,  2,  2,  3,  4,  4,  5,  6,  6,  7,  8,  8,  9, 10
		.BYTE   0,  1,  1,  2,  2,  3,  4,  5,  5,  6,  7,  8,  8,  9, 10, 11
		.BYTE   0,  1,  1,  2,  3,  4,  4,  5,  6,  7,  8,  8,  9, 10, 11, 12
		.BYTE   0,  1,  1,  2,  3,  4,  5,  6,  6,  7,  8,  9, 10, 11, 12, 13
		.BYTE   0,  1,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14
		.BYTE   0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15

; =========================================================================================
		
Nesori_updatePulse: ; only one pulse	
		LDA Nesori_chVolDutyEnvPtrL,X ; do volduty envelope
		STA Nesori_temp_ptr+0
		LDA Nesori_chVolDutyEnvPtrH,X
		STA Nesori_temp_ptr+1
		LDY Nesori_chVolDutyEnvIndex,X
		INC Nesori_chVolDutyEnvIndex,X

		LDA (Nesori_temp_ptr),Y
		AND #$20 ; bit 5 check
		BNE @noenvloop
		DEY ; push pointer to right previous byte
		DEC Nesori_chVolDutyEnvIndex,X
@noenvloop:
		LDA (Nesori_temp_ptr),Y
		AND #$F0
		STA Nesori_temp_ptr2+0
		LDA (Nesori_temp_ptr),Y
		AND #$0F
		ORA Nesori_chVol,X
		TAY
		LDA Nesori_volTbl,Y
		ORA Nesori_temp_ptr2+0

		LDY @chregoffset,X ; $4000/$4004
		STA $4000,Y
		
		LDA #0
		STA Nesori_temp_ptr2+0 ; for high byte of pitch envelope
		STA Nesori_temp_ptr2+1
		LDA Nesori_chPitch,X ; get high byte first
		BPL @pitchoffsetispositive
		DEC Nesori_temp_ptr2+1 ; $FF
@pitchoffsetispositive:

		LDA Nesori_chPitchEnvPtrL,X ; do pitch envelope
		STA Nesori_temp_ptr+0
		LDA Nesori_chPitchEnvPtrH,X
		STA Nesori_temp_ptr+1
		LDY Nesori_chPitchEnvIndex,X
		INC Nesori_chPitchEnvIndex,X
		
		LDA (Nesori_temp_ptr),Y
		CMP #$80
		BNE @nopitchenvloop
		INY
		LDA (Nesori_temp_ptr),Y ; read loop index
		STA Nesori_chPitchEnvIndex,X
		TAY
		LDA (Nesori_temp_ptr),Y
@nopitchenvloop:
		BPL @pitchenvelopeispositive
		DEC Nesori_temp_ptr2+0 ; $FF
@pitchenvelopeispositive:
		CLC
		ADC Nesori_chPitch,X
		TAY
		LDA Nesori_temp_ptr2+0
		ADC Nesori_temp_ptr2+1
		STA Nesori_temp_ptr2+1
		STY Nesori_temp_ptr2+0
		
		LDA Nesori_chBaseNote,X
		AND #$0F ; note
		TAY
		LDA Nesori_periodTableLsb,Y
		STA Nesori_temp_ptr+0
		LDA Nesori_periodTableMsb,Y
		STA Nesori_temp_ptr+1
		LDA Nesori_chBaseNote,X
		AND #$F0 ; octave
		LSR
		LSR
		LSR
		LSR
		TAY
		LDA Nesori_temp_ptr+0
@shiftloop:
		LSR Nesori_temp_ptr+1
		ROR
		DEY
		BPL @shiftloop
		CLC
		ADC Nesori_temp_ptr2+0
		LDY @chregoffset,X ; $4002/$4006, $4003/$4007
		STA $4002,Y
		LDA Nesori_temp_ptr+1
		ADC Nesori_temp_ptr2+1
		AND #$03
		ORA #$08
		CMP Nesori_oldHighPeriodReg,X
		BEQ @nochange
		STA Nesori_oldHighPeriodReg,X
		STA $4003,Y
@nochange:
		RTS
		
@chregoffset: .BYTE 0, 4