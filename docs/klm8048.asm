;
; Korg Trident mk2/Polysix patch manager program disassembly
;
; Micro: 8048 
; Xtal used: 6MHz
; 	Machine clock: 2.5us
; 	Timer freq: 12.5kHz (period=80us) 
;
; 

	org	0
;
RESET:
	anl	p1,#1fh		; p1=00011111b
	clr	a
	call	REFRESH_P_LED	; Turn off all LEDs
	call	REFRESH_B_LED	; ...
	mov	psw,a		; Clear PSW
	in	a,p1
	jb4	NRML_MODE	; Check if in test mode
	jmp	TEST_MODE	; Go to test mode routine
;
NRML_MODE:			; Normal mode
	sel	rb1
	mov	r1,#14h		; 
	mov	a,#1
	mov	@r1,a		; Light LED "A" when patch is loaded
	inc	r1
	mov	@r1,a		; Light LED "1" when patch is loaded
	inc	r1
	clr	a
	mov	@r1,a		; Clear data of program buttons state
	inc	r1
	mov	@r1,a		; Clear data of bank buttons state
	mov	r3,#40h
	mov	r6,a		; Set ext. RAM address for 
	clr	f0		;    loading patch A1
	jmp	LOAD_A1		; Jump to load A1
;
CV_SCAN_INIT:			; (Note: rb0 selected)
	mov	a,#0dh		;
	mov	r7,a		; Reset output data MUX counter
	inc	a
	mov	r5,a		; Init loop counter
	mov	r6,#0		; Reset input data MUX counter
CV_SCAN_LOOP:			; Scan front panel pots
	call	SAR_ROUTINE	; Do AD conversion
	mov	a,#0fdh		; Initialize timer (period 240us)
	mov	t,a		; ...
	strt	t
	mov	a,r7
	outl	p2,a		; Set output MUX address...
	add	a,#20h		; ...add offset for memory pointer 
	mov	r0,a		; ...set pointer 
	mov	a,@r0		; Get value from memory
	outl	bus,a		; Value to DAC
	orl	p1,#40h		; Set p1.6 (enable output MUXes)

; Process new CV data
	mov	a,#20h		;
	add	a,r6		;
	mov	r0,a		; r0 points to patch memory (20...2Fh)
	mov	r1,#10h		; Init manual flag register pointer
	mov	a,#0f8h		; Check if r6>=8
	add	a,r6		; 
	jc	PROC_CV_HI_ADR	; Jump if r6>=8
	mov	a,r6
	jmp	PROC_CV_LO_ADR
PROC_CV_HI_ADR:
	inc	r1		; If r6 >=8, increment flag register pointer
PROC_CV_LO_ADR:
	add	a,#0efh
	movp3	a,@a		; Decode (3->8) r6 value
	mov	r3,a		; Store decoded value
	mov	a,r1
	sel	rb1
	add	a,#0fch
	mov	r1,a		; r1(bank1)=r1(bank0)-4 (=0Ch or 0Dh) 
	sel	rb0
	mov	a,r3		; Get decoded value from memory
	anl	a,@r1		; Check if manual flag was set previously
	jnz	PROC_CV_MANUAL	;   Jump if manual flag set 
	dec	r1
	dec	r1		; r1=0Eh or 0Fh
	mov	a,@r1		; If this flag set, previous CV value
	anl	a,r3		;  was either 0 or FFh 
	jz	PROC_CV_MINMAX_CHECK ; Jump if masked bit cleared
	mov	a,#0feh
	add	a,r4		
	jnc	PROC_CV_CHANGE_CHECK ; Jump if AD value < 2
	mov	a,#2
	add	a,r4
	jc	PROC_CV_CHANGE_CHECK ; jump if AD value > 253
	inc	r1
	inc	r1		; r1=10h or 11h
	mov	a,@r1
	orl	a,r3
	mov	@r1,a		; Set flag in memory 10h or 11h
	jmp	PROC_CV_MANUAL
;
PROC_CV_MINMAX_CHECK:
	mov	a,r4		; Check if AD value either 0 or FFh
	jz	PROC_CV_MINMAX	; Jump if AD value 0
	cpl	a
	jnz	PROC_CV_CHANGE_CHECK ; Jump if AD value isn't FFh
PROC_CV_MINMAX:
	mov	a,@r1		
	orl	a,r3		
	mov	@r1,a 		; Set Min/Max flag in memory 0E or 0Fh
PROC_CV_CHANGE_CHECK:
	mov	a,#30h
	add	a,r6
	mov	r1,a		; r1 points to current CV memory (30...3Dh)
	mov	a,@r1
	cpl	a
	inc	a		; Binary complement
	add	a,r4		; Calculate difference between previous and
	mov	r2,a		;   current CV and store it to r2 
	mov	a,r3
	sel	rb1
	anl	a,@r1		; Check movement flag in 0Ch(0Dh)
	sel	rb0
	jnz	PROC_CV_DO_CHANGE ; 
	mov	a,r2		; See if difference is negative
	jb7	PROC_CV_DIF_NEG	 
	jmp	PROC_CV_DIF_POS
;
PROC_CV_DIF_NEG:
	cpl	a
	inc	a		; Get absolute value of difference
PROC_CV_DIF_POS:
	add	a,#0fdh		; Check if absolute difference > 2 
	jnc	CV_SCAN_CHECK_TIMER ; Skip, parameter hasn't changed
	mov	a,r3	
	sel	rb1
	orl	a,@r1		; Set corresponding flag in 0Ch (0Dh)
	mov	@r1,a		;....
	sel	rb0
PROC_CV_DO_CHANGE:
	mov	a,r2		; See if difference is negative
	jb7	PROC_CV_ADD_DIF_NEG
	add	a,@r0	 	; Add difference to patch data
	jnc	PROC_CV_ADD_DIF_POS ; Proceed if result isn't too big
	clr	a
	cpl	a		; If result too big, write FFh
	jmp	PROC_CV_ADD_DIF_POS
;
PROC_CV_ADD_DIF_NEG:
	add	a,@r0		; Add difference to patch data
	jc	PROC_CV_ADD_DIF_POS ; Proceed if result isn't negative 
	clr	a		; If result negative, write zero
PROC_CV_ADD_DIF_POS:
	mov	@r0,a		; Store new value to 20...2Dh (patch data) 
	mov	a,r4		; 
	mov	@r1,a		; Store current CV value to 30...3Dh
	jmp	CV_SCAN_CHECK_TIMER
;
PROC_CV_MANUAL:
	mov	a,r4		; Store current CV value to patch 
	mov	@r0,a		;   memory (20...2Dh)
CV_SCAN_CHECK_TIMER:
	jtf	PROCESS_SW_INIT	; Wait until timer overflows
	jmp	CV_SCAN_CHECK_TIMER
;
PROCESS_SW_INIT:
	stop	tcnt
	mov	a,r6
	mov	r7,a
	inc	r6
	anl	p1,#0bfh		; Clear p1.6
	djnz	r5,CV_SCAN_LOOP
	mov	r0,#2eh
	mov	r1,#12h
	mov	r5,#0
	sel	rb1
	mov	r0,#3eh
	mov	r2,#0feh
	mov	r3,#10h
	sel	rb0
	mov	r6,#2
PROC_SW_LOOP:
	call	SWITCH_SCAN	; Read current VCO1 octave,WF,Kbd. Track
	mov	r4,a		;     (AutoDamp, VCO2 octave,Attenuator)
	sel	rb1
	xrl	a,@r0		; Compare with previous state in 3Eh (3Fh)
	sel	rb0
	mov	r2,a		; Store the difference 
	mov	a,#0c9h		; 
	add	a,r0		; r0=C9h+2Eh (+1)
	movp3	a,@a		; Get number of parameters from 3f7h = 04 
	mov	r7,a		;				(3F8h = 3)
PROC_SW_LOOP2:
	mov	a,r5		;
	add	a,#0f9h		; 
	movp3	a,@a		; Get bit mask for current parameter and 
	mov	r3,a		; store it into R3
	anl	a,@r1		; Check for differences from 12h (13h)
	jnz	PROC_SW_PREV_CHANGED ; The parameter was already changed
	mov	a,r2
	anl	a,r3		; Check if parameter has changed
	jz	PROC_SW_NO_CHANGE	;
	mov	a,@r1		; Set flags to indicate that parameter changed
	orl	a,r3
	mov	@r1,a
PROC_SW_PREV_CHANGED:
	mov	a,r3
	cpl	a
	anl	a,@r0		; Get switch data from 2Eh(2Fh) w/o currently tested
	xch	a,r3		;  one, store it to r3  
	anl	a,r4		; filter out current parameter data 
	orl	a,r3		; merge with the rest of previous switch data
	mov	@r0,a		; Store the data with new parameter value to 2Eh(2Fh)
PROC_SW_NO_CHANGE:
	inc	r5
	djnz	r7,PROC_SW_LOOP2	; Loop 4 (3) times
	mov	a,@r0
	outl	bus,a		; Put processed data to bus 
	inc	r0		; Reinitialize some variables
	inc	r1		; ....
	sel	rb1
	in	a,p2		; 
	orl	a,r3		; Set p2.4(p2.5)
	outl	p2,a		; Enable switch data output latches
	inc	r0		; 
	mov	a,r3
	rl	a
	mov	r3,a		; 
	sel	rb0
	anl	p2,#0fh		; Clear p2[7:4]
	djnz	r6,PROC_SW_LOOP ; Loop twice to process all sw. data
	jni	PROC_SW_TAPE_DIS ; Jump if Tape Enabled
	jmp	CHECK_P_BUTTONS
PROC_SW_TAPE_DIS:
	jmp	TAPE_EN_CANCEL
;
CHECK_P_BUTTONS:
	orl	p1,#20h		; Set p1.5(testpoint on P6,N/C on Trident) 
	mov	r1,#16h
	call	SWITCH_SCAN	; Read current VCO1 octave,WF,Kbd. Track
	xch	a,@r1		; Read previous button states
	cpl	a		; Detect only falling edge (key pressed)
	anl	a,@r1		; ...
	jnz	P_BUTTON_CHANGE	; Jump if some button was pressed 
	jmp	CHECK_B_BUTTONS ; Jump if no change
;
P_BUTTON_CHANGE:
	mov	r2,#0ffh
P_BUTTON_ENC_LOOP:
	inc	r2		; Primary encoder (8->3, lowest bit counts) 
	rrc	a
	jnc	P_BUTTON_ENC_LOOP
	dec	r1		; 15h
	mov	a,#0efh
	anl	a,@r1		; Clear bit4 of 15h (manual LED off)
	mov	@r1,a
	mov	r3,a
	dec	r1
	mov	a,#0efh
	add	a,r2
	movp3	a,@a		; Decode (3->8) R2
	mov	@r1,a		; Light LED corresponding to button pressed
	mov	a,r2		
	swap	a
	sel	rb1		; Set r6 for patch loading (stores first
	xch	a,r6		; patch data external RAM byte address)
	anl	a,#80h		; Leave bit 7 as is (signalizes patch bank)
	orl	a,r6		; 
	mov	r6,a		; 
	sel	rb0
	mov	a,#20h
	anl	a,r3		; If bit5 in r3 set, write button was
	jnz	SAVE_PATCH	; previously pressed, so save current patch
	jmp	LOAD_PATCH
;
CHECK_B_BUTTONS:
	inc	r1		; =17h
	call	SWITCH_SCAN	; Read Bank, Manual, Write, Write En. buttons
	xch	a,@r1		; Read previous button states
	cpl	a		; Detect only falling edge (key pressed)
	anl	a,@r1		; ...
	mov	r4,a		; Store that to r4 
	mov	a,#40h		; Makes sure Write enable state is unchanged
	anl	a,@r1		;  in the process
	orl	a,r4		; ...
	mov	r4,a		; ...
	dec	r1
	dec	r1		; =15h
	anl	a,#0fh		; Check if Bank button was pressed
	jz	CHECK_WR_MAN	; No, check Write and Manual buttons
	mov	r2,#0ffh
B_BUTTON_ENC_LOOP:
	inc	r2		; Primary encoder (8->3, lowest bit counts) 
	rrc	a
	jnc	B_BUTTON_ENC_LOOP
	mov	a,#0efh
	add	a,r2
	movp3	a,@a		; Decode (3->8) R2
	xch	a,@r1		; Light LED corresponding to pressed bank button
	anl	a,#0f0h		; ...
	orl	a,@r1		; ...
	mov	@r1,a		; ...
	mov	r3,a
	mov	a,r2
	cpl	a
	clr	f0		; Set ext. RAM address for possible saving/loading
	jb1	B_BUTTON_BANK_AB
	cpl	f0		; Set f0 if bank button C of D was pressed
B_BUTTON_BANK_AB:
	sel	rb1
	jb0	B_BUTTON_BANK_AC
	mov	a,#80h
	orl	a,r6		; Set r6.7 if bank button B or D was pressed 
	jmp	B_BUTTON_BANK_BD
;
B_BUTTON_BANK_AC:
	mov	a,#70h
	anl	a,r6		; Clear r6.7 if bank button A or C was pressed 
B_BUTTON_BANK_BD:
	mov	r6,a
	sel	rb0
	mov	a,#20h
	anl	a,r3		; Check if in Write mode (Write LED lit)
	jnz	B_BUTTON_WRITE
	mov	a,#10h
	anl	a,r3		; Check if in Manual mode (Manual LED lit)
	jnz	B_BUTTON_MANUAL
	jmp	LOAD_PATCH	; If not in Manual and Write mode, load patch 
;
CHECK_WR_MAN:
	mov	a,#10h
	anl	a,r4		; Check if Manual button was pressed previously
	jz	B_BUTTON_MANUAL
	mov	a,@r1		; r1=15h
	orl	a,#10h		; Light up Manual LED
	anl	a,#0dfh		; Turn of Write LED
	mov	@r1,a
	dec	r1
	clr	a
	mov	@r1,a		; Turn off number (program) LEDs
	cpl	a
	mov	r0,#4
SET_MANUAL_LOOP:
	dec	r1		; values 13h...10h
	mov	@r1,a		; Set manual flags for all parameters
	djnz	r0,SET_MANUAL_LOOP ; Loop 4 times
	jmp	SET_LED
;
B_BUTTON_MANUAL:
	mov	r1,#15h
	mov	a,#20h
	anl	a,@r1		; Check if in Write mode (Write LED lit)
	jz	B_BUTTON_NOT_WRITE_MODE
B_BUTTON_WRITE:
	mov	a,r4
	anl	a,#40h		; Check if Write enabled 
	jz	WRITE_MODE_EXIT	; If not, exit Write mode
	sel	rb1
	mov	a,#5
	add	a,r7
	jmp	WRITE_MODE_NO_CHANGE
;
B_BUTTON_NOT_WRITE_MODE:
	mov	a,r4
	cpl	a		; Check if Write was pressed  
	anl	a,#60h		;  and Write Enabled 
	jz	WRITE_MODE_SET ; 
	jmp	SET_LED
;
WRITE_MODE_SET:
	mov	a,@r1
	orl	a,#20h		; Light Write LED
	mov	@r1,a
	sel	rb1
	clr	a
WRITE_MODE_NO_CHANGE:
	mov	r7,a
	jmp	SET_LED
;
WRITE_MODE_EXIT:
	mov	a,@r1
	anl	a,#0dfh		; Turn off Write LED 
	mov	@r1,a
	jmp	SET_LED
;
SAVE_PATCH:
	sel	rb1
	mov	r0,#20h
	mov	a,r6
	mov	r1,a
	clr	a
	jf0	SAVE_PATCH_BANK_C ; if f0 set, patch bank C or D
	jmp	SAVE_PATCH_BANK_A
SAVE_PATCH_BANK_C:
	orl	a,#2
SAVE_PATCH_BANK_A:
	outl	p2,a
	mov	r5,#10h
SAVE_PATCH_LOOP:
	mov	a,@r0
	call	BYTE_TO_XRAM		; Store 20h...2Fh to ext. RAM
	inc	r0
	djnz	r5,SAVE_PATCH_LOOP	; Loop 16 times
	sel	rb0
	jmp	SAVE_PATCH_REINIT	; Reinitialize some registers
;
LOAD_PATCH:	
	sel	rb1	
LOAD_A1:				; At startup load patch A1
	mov	r0,#20h
	mov	a,r6
	mov	r1,a
	mov	a,#1
	jf0	LOAD_PATCH_BANK_C	; Set flag means patch bank C or D 
	jmp	LOAD_PATCH_BANK_A
LOAD_PATCH_BANK_C:
	orl	a,#2
LOAD_PATCH_BANK_A:
	outl	p2,a
	mov	r5,#10h
LOAD_P_LOOP:
	call	BYTE_FROM_XRAM	; Get patch data from ext. RAM and
	mov	@r0,a		;  store it to memory 20h...2Fh 
	inc	r0
	djnz	r5,LOAD_P_LOOP	; Loop 16 times
	sel	rb0
SAVE_PATCH_REINIT:
	mov	r1,#0ch
	clr	a
	mov	r2,#8
LOAD_P_LOOP2:
	mov	@r1,a		; Clear memory 0Ch...13h
	inc	r1
	djnz	r2,LOAD_P_LOOP2	; Loop 8 times
	mov	r6,#0
	mov	r0,#30h
	mov	r5,#0eh
LOAD_P_LOOP3:
	call	SAR_ROUTINE	; Read all pot CV values and
	mov	@r0,a		; store them to memory 30h..3Dh
	inc	r0
	inc	r6
	djnz	r5,LOAD_P_LOOP3	; Loop 14 times
	mov	r0,#3eh
	sel	rb1
	mov	r2,#0feh	
	call	SWITCH_SCAN	; Read VCO1 octave,WF,Kbd Track and
	mov	@r0,a		;  store current settings to 3Eh
	inc	r0
	call	SWITCH_SCAN	; Read Autodamp,VCO2 octave,Attenuator and
	mov	@r0,a		;  store current settings to 3Fh
	mov	r1,#15h
	jmp	WRITE_MODE_EXIT ; Jump to exit possible Write mode
;
SET_LED:
	sel	rb1
	mov	r0,#14h
	mov	a,@r0
	call	REFRESH_P_LED	; Show current program position with LEDs 
	inc	r0
	mov	a,r7		; ??? This is weird flashing LED thingie
	rr	a		; ...... I think... :)
	anl	a,r7		; ... 
	rr	a		; ...
	anl	a,#20h		; Makes sure Write LED doesn't light up 
	cpl	a
	anl	a,@r0
	call	REFRESH_B_LED	; Show current program position with LEDs 
	sel	rb0
	anl	p1,#0dfh	; Clear p1.5(testpoint on P6,N/C on Trident) 
	jmp	CV_SCAN_INIT
;
;
;
;
;
SAR_ROUTINE:		; ADC succesive approximation routine (returns value in Acc and R4)
			; r2-bit counter
			; r3-weighting bit
			; r4-ADC value
	mov	a,r6
	anl	a,#0fh
	outl	p2,a	; p2<-r6[3:0] 
	mov	r3,#80h	; r3<-80h
	clr	a
	mov	r4,a	; Clear R4
	mov	r2,#8	; Set bit counter
SAR_LOOP:	
	add	a,r3	; Add weight to value
	outl	bus,a	; Output value
	xch	a,r3	; Rotate r3
	rr	a	; ...
	xch	a,r3	; ...
	jnt0	SAR_NO_ADD	; 
	mov	r4,a	; If T0=1 set new value to r4 (add weight),
SAR_NO_ADD:
	mov	a,r4	; otherwise leave it unchanged
	djnz	r2,SAR_LOOP ; Loop until bit counter is zero
	ret
;
SWITCH_SCAN:		; Scans front panel buttons and switches
			; Returns value in Acc
			; r2(bank1)-switch mask
	sel	rb1
	mov	a,r2
	outl	bus,a	; Mask p2
	rl	a	; Rotate mask
	mov	r2,a	; Save rotated mask
	in	a,p1	; Read 4 switches
	orl	a,#0f0h	
	mov	r5,a	; Store to R5
	mov	a,r2
	outl	bus,a	;
	rl	a
	mov	r2,a
	in	a,p1	;
	swap	a
	orl	a,#0fh
	anl	a,r5	; Merge both read values
	cpl	a
	sel	rb0
	ret
;
BYTE_FROM_XRAM:
	orl	p1,#80h		; Set p1.7
	anl	p2,#0feh
	movx	a,@r1
	anl	a,#0fh
	mov	r2,a
	orl	p2,#1
	movx	a,@r1
	anl	p1,#7fh		; Clear p1.7
	swap	a
	anl	a,#0f0h
	orl	a,r2
	inc	r1
	ret
;
BYTE_TO_XRAM:
	orl	p1,#80h		; Set p1.7
	anl	p2,#0feh
	movx	@r1,a
	swap	a
	orl	p2,#1
	movx	@r1,a
	anl	p1,#7fh		; Clear p1.7
	inc	r1
	ret
;
BYTE_FROM_TAPE:			; Returns with byte value in Acc
	call	TAPE_DATA_RX	; Dummy read
	jc	BYTE_FROM_TAPE	; Repeat until edge is detected
	mov	r7,#8
BYTE_FROM_TAPE_L:	
	call	TAPE_DATA_RX	; Read one bit
	xch	a,r3
	rrc	a		; rotate the intermidiate result 
	xch	a,r3
	djnz	r7,BYTE_FROM_TAPE_L	; Repeat read 8 times
	mov	a,r3		; Put tape byte value to Acc
	ret
;
TAPE_DATA_RX:		; Receive tape data bit
	clr	c
	mov	r2,#0
	jf1	TAPE_IN_1	; Check if tape input line changed
TAPE_IN_0:
	jt1	TAPE_IN_CHANGE	; ...
	djnz	r2,TAPE_IN_0
	jmp	TAPE_IN_NO_CHANGE
TAPE_IN_1:
	jnt1	TAPE_IN_CHANGE
	djnz	r2,TAPE_IN_1
TAPE_IN_NO_CHANGE:		; Gets here if no T1 change in 2.5ms
	mov	r5,#1
	mov	r6,#1
TAPE_IN_CHANGE:
	cpl	f1
	jtf	TAPE_IN_TIMEOUT
	cpl	c		; Set C if line changes within timer period
TAPE_IN_TIMEOUT:
	mov	a,#0fah
	mov	t,a		; Reinitialize timer (period 480us)
	call	SUB13
	ret
;
BYTE_TO_TAPE:
	mov	r3,a
	clr	c
	call	TAPE_DATA_TX
	mov	r7,#8
BYTE_TO_TAPE_LOOP:
	mov	a,r3
	rrc	a
	mov	r3,a
	call	TAPE_DATA_TX
	djnz	r7,BYTE_TO_TAPE_LOOP ; Loop 8 times
	clr	c
	cpl	c
	call	TAPE_DATA_TX
	call	TAPE_DATA_TX
	ret
;
TAPE_DATA_TX:			; Dump one bit to tape
	call	CHECK_TAPE_EN
	in	a,p2		; Check current tape output state
	jb2	TAPE_OUT_1	; Jump if p2.2 set 
	orl	a,#0ch		; if currently p2.2=0, set p2.2 and p2.3
	jmp	TAPE_OUT_0
;
TAPE_OUT_1:
	anl	a,#3		; if currently p2.2=1, clear p2.2 and p2.3
TAPE_OUT_0:
	mov	r2,a		; Store new tape out state to r2
	mov	a,#0fch		; Prepare timer reinit value (period 320us)
	jc	TAPE_OUT_TMR_L	; If C=1, timer value is OK
	rlc	a		; If C=0, double timer reinit value (period 640us)
	xch	a,r2
	xrl	a,#8		; Toggle r2.3 (p2.3)
	xch	a,r2
TAPE_OUT_TMR_L:
	jtf	TAPE_OUT_TMR_DONE ; Wait for timer overflow
	jmp	TAPE_OUT_TMR_L
;
TAPE_OUT_TMR_DONE:
	mov	t,a		; Reinit timer
	mov	a,r2
	outl	p2,a		; Refresh tape output
	ret
;
TAPE_STRING_DETECT:
	call	BYTE_FROM_TAPE
	xrl	a,#50h
	jnz	TAPE_STRING_DETECT
	call	BYTE_FROM_TAPE
	xrl	a,#36h
	jnz	TAPE_STRING_DETECT
	ret
;
REINIT_XRAM_ADDR:		; 
	mov	r0,#0
	mov	r5,#2			
	anl	p2,#0fdh	 ;clear P2.1 (external RAM pin A9)
	ret
;
REFRESH_P_LED:
	outl	bus,a	
	orl	p2,#40h		; Enable program LED latch
	anl	p2,#0bfh	; Disable program LED latch
	ret
;
REFRESH_B_LED:
	outl	bus,a
	orl	p2,#80h		; Enable bank LED latch
	anl	p2,#7fh		; Disable bank LED latch
	ret
;
CHECK_GLOBAL_SETTINGS:
	jf0	CHECK_WRITE_EN
	jmp	CHECK_TAPE_EN
;
CHECK_WRITE_EN:		; If f0=1, write operation is about to take place 
	mov	a,#7fh
	outl	bus,a	; clear D0.7
	in	a,p1	; Read Manual,Write,Write enable buttons
	jb2	CHK_GL_SET_RET	; Jump if Write disabled
	jmp	CHECK_TAPE_EN	; Jump if Write enabled
CHK_GL_SET_RET:
	jmp	TAPE_EN_CANCEL
;
CHECK_TAPE_EN:
	jni	TAPE_EN_READ_BANK ; Jump if tape enabled (patch dump mode)
	jmp	RESET		; Restart if tape disabled (normal mode)
;
TAPE_EN_READ_BANK:
	mov	a,#0bfh
	outl	bus,a		; clear D0.6
	in	a,p1		; Read Bank buttons
	jb3	TAPE_EN_RETURN	; Return if Cancel isn't pressed
	jmp	TAPE_EN_CANCEL		; Jump if Cancel is pressed (clear LEDs and PSW)
TAPE_EN_RETURN:	
	ret
;
TAPE_REFR_LEDS:
	call	REFRESH_B_LED
	clr	a
	mov	r4,a
	call	REFRESH_P_LED
	strt	t
	ret
;
PROGRESS_BAR:			; Progress indicator routine
	mov	a,#0c0h		; Check if r1=xx111111b
	orl	a,r1
	cpl	a		
	jnz	PROGRESS_BAR_RETURN	; Return
	mov	a,r4		; Light new program LED every 64 calls of this routine
	clr	c
	cpl	c		; Set carry
	rlc	a
	mov	r4,a	
	call	REFRESH_P_LED	; Refresh program LEDs
PROGRESS_BAR_RETURN:
	ret
;
DUMMY_DUMP:			; 
	clr	c
	cpl	c		;Set carry
	mov	r7,#0
DUMMY_DUMP_LOOP:
	call	TAPE_DATA_TX
	djnz	r7,DUMMY_DUMP_LOOP	; Loop 256 times
	djnz	r6,DUMMY_DUMP_LOOP
	ret
;
TAPE_EN_CANCEL:
	clr	a
	call	REFRESH_P_LED	; Turn off LEDs
	call	REFRESH_B_LED	; ...
	mov	psw,a		; Clear status
TAPE_EN_CHECK_BUTTONS:
	clr	f0
	stop	tcnt
	call	CHECK_TAPE_EN	; Read Bank buttons
	cpl	a		; Invert
	jb0	TAPE_DUMP	; Jump if "To tape" (A) is pressed
	jb2	TAPE_VERIFY	; Jump if "Verify" (C) is pressed
	jb1	TAPE_READ	; Jump if "From tape" (B) is pressed
	jmp	TAPE_EN_CHECK_BUTTONS
;
TAPE_DUMP:
	mov	a,#1		; A pressed
	call	TAPE_REFR_LEDS	; Light A LED, clr P LEDs, clr r4
	mov	r6,#28h
	call	DUMMY_DUMP	; Send 10240 (=40x256) dummy "ones" to tape output
	mov	a,#50h
	call	BYTE_TO_TAPE
	mov	a,#36h
	call	BYTE_TO_TAPE	; Dump string "50h,36h"
	call	REINIT_XRAM_ADDR	; r0=0,r5=2,RAM adr=00
	jmp	TAPE_D_PROCEED
;
TAPE_D_LOOP:
	orl	p2,#2		; Set p2.1 (external RAM line A9) after 
				; first 256 executions of loop 
TAPE_D_PROCEED:
	mov	r6,#0
	mov	r1,#0
TAPE_D_LOOP2:
	call	BYTE_FROM_XRAM	; Get byte from memory
	xch	a,r0		; Calculate checksum:
	add	a,r0		; Add Acc value to r0,
	xch	a,r0		; Acc doesn't change...
	call	BYTE_TO_TAPE	; Dump byte to tape
	call	PROGRESS_BAR	; Refresh Progress indicator
	djnz	r6,TAPE_D_LOOP2
	djnz	r5,TAPE_D_LOOP	; Loop 512 times (whole memory)  
	mov	a,r0
	call	BYTE_TO_TAPE	; Dump checksum
	mov	r6,#6
	call	DUMMY_DUMP	; Send 1536 dummy "ones" to tape
	jmp	TAPE_EN_CANCEL
;
TAPE_READ:
	cpl	f0
	call	CHECK_GLOBAL_SETTINGS
	mov	a,#2
	call	TAPE_REFR_LEDS	; Light B LED, clr program LEDs, clr r4
	call	TAPE_STRING_DETECT	; Wait for string "50h,36h" at tape input
	mov	a,#32h
	call	REFRESH_B_LED		; Light Manual, Write and B LEDs
	call	REINIT_XRAM_ADDR	; r0=0,r5=2,RAM adr=00
	jmp	TAPE_R_PROCEED
;
TAPE_R_LOOP:
	orl	p2,#2		; Set p2.1 (external RAM line A9) after 
				; first 256 executions of loop 
TAPE_R_PROCEED:
	mov	r6,#0
	mov	r1,#0
TAPE_R_LOOP2:
	call	BYTE_FROM_TAPE	; Get byte from tape
	xch	a,r0		; Calculate checksum:
	add	a,r0		; Add Acc value to r0,
	xch	a,r0		; Acc doesn't change...
	call	BYTE_TO_XRAM	; Store byte to external RAM
	call	PROGRESS_BAR	; Refresh progress indicator
	djnz	r6,TAPE_R_LOOP2
	djnz	r5,TAPE_R_LOOP	; Loop 512 times (whole memory)
VERIFY_CHECKSUM:
	call	BYTE_FROM_TAPE	; Read checksum from tape
	xrl	a,r0		; Compare
	jnz	VERIFY_ERROR	; Error if values don't match
	jmp	TAPE_EN_CANCEL
;
TAPE_VERIFY:
	mov	a,#4
	call	TAPE_REFR_LEDS	; Light C LED, clr P LEDs, clr r4
	call	TAPE_STRING_DETECT
	mov	a,#14h
	call	REFRESH_B_LED	; Light Manual LED
	call	REINIT_XRAM_ADDR	; r0=0,r5=2,RAM adr=00
	jmp	VERIFY_PROCEED
;
VERIFY_LOOP:
	orl	p2,#2		; Set p2.1 (external RAM line A9) after 
				; first 256 executions of loop 
VERIFY_PROCEED:
	mov	r6,#0
	mov	r1,#0
VERIFY_LOOP2:
	call	BYTE_FROM_TAPE	; Read byte from tape
	xch	a,r0		; Calculate checksum:
	add	a,r0		; Add Acc value to r0,
	xch	a,r0		; Acc doesn't change...
	mov	r3,a
	call	BYTE_FROM_XRAM	; Get byte from external RAM
	xrl	a,r3		; Compare values
	jnz	VERIFY_ERROR	; If not zero, verify fails
	call	PROGRESS_BAR	; Values match, refresh progress bar
	djnz	r6,VERIFY_LOOP2
	djnz	r5,VERIFY_LOOP	; Loop 512 times (whole memory)
	jmp	VERIFY_CHECKSUM
;
VERIFY_ERROR:
	mov	a,#8
	call	REFRESH_B_LED	; Light D (Error) LED
	jmp	TAPE_EN_CHECK_BUTTONS
;
TEST_MODE:			; Test mode
	mov	r0,#0ch		; Point to address 0Ch
TEST_M_LOOP:
	mov	r1,#0ch		; Point to address 0Ch
	mov	r6,#0		; r6 goes to p2 
	call	SAR_ROUTINE	; Get ADC value (VCA Attack)
	call	DEC_2_4_OFFSET	; Store to 0Ch
	inc	r1
	inc	r6
	call	SAR_ROUTINE	; Get ADC value (VCA Decay)
	cpl	a		; Invert value
	call	DEC_2_4_OFFSET	; Store to 0Dh
	mov	r2,#4		; Loop TEST_M_L2 4 times
TEST_M_L2:			;
	xch	a,@r1		; Swap nibbles of byte 0Ch,
	rlc	a		; swap high nibble bits of 0Dh,
	xch	a,@r1		; and move 0Dh[7:4] to 0Ch[7:4] 
	xch	a,@r0		; ...
	rrc	a		; ...
	xch	a,@r0		; ...
	djnz	r2,TEST_M_L2
	mov	a,@r0		; Move calculated value from 0Ch
	call	REFRESH_P_LED	; Display this calculated value
	jmp	TEST_M_LOOP
;
DEC_2_4_OFFSET:			; Decode Acc[2:1] to memory[7:4]
				; Input value in Acc
				; Output to memory to which points R1
	jnz	DEC_2_4_P1	
	mov	@r1,#10h	; @r1=10h if Acc=0
	ret
;
DEC_2_4_P1:
	add	a,#0feh		; Acc=Acc-2
	jc	DEC_2_4_P2
	mov	@r1,#20h	; @r1=20h if Acc=1
	ret
;
DEC_2_4_P2:
	add	a,#0feh		; Acc=Acc-2
	jc	DEC_2_4_P3
	mov	@r1,#40h	; @r1=40h if Acc=2,3
	ret
;
DEC_2_4_P3:
	mov	@r1,#80h	; @r1=80h if Acc>=4
	ret
;
;
; Look-up Tables:
;
	org	3efh
;
; 3-to-8 encoder table
;
 .DB	01h,02h,04h,08h,10h,20h,40h,80h
;
; Switch parameter number
;
 .DB 4,3
;
; Switches1 bit masks 
;
 .DB 03h,0Ch,30h,C0h
;
; Switches2 bit masks
;
 .DB 01h,0Eh,F0h

	end

