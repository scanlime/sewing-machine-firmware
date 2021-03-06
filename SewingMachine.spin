{{

SewingMachine
-------------

This is a Parallax Propeller object which encapsulates the
low-level control of my sewing machine. It includes a PWM
motor driver, sensors for estimating position and speed,
pedal input, and some basic sewing control functions.

This file is a library that provides this low-level
functionality only. The main program is responsible for
implementing individual sewing modes.

┌──────────────────────────────────────────┐
│ Copyright (c) 2008 Micah Dowty           │               
│     See end of file for terms of use.    │               
└──────────────────────────────────────────┘

}}                  

CON

  PIN_TACHOMETER  = 22   ' Input from optical tachometer amplifier
  PIN_PEDAL       = 21   ' RC circuit for pedal input
  PIN_INTERRUPTER = 20   ' Photo-interrupter for needle up/down reference 
  PIN_DIRECTION   = 19   ' Direction control for motor
  PIN_BRAKE       = 18   ' Break output for motor
  PIN_PWM         = 17   ' PWM output for motor
  PIN_THERMAL     = 16   ' Thermal warning flag from motor controller

  PEDAL_MIN  = 1960     ' End of dead zone
  PEDAL_MAX  = 170      ' Fully pressed
  
  ' Sensor calibration
  '
  '   Calibrating:
  '     1. Disable the use of CYCLE_INTR_LOW in the sensor cog
  '     2. Set TACH_RATIO to 1
  '     3. Measure SENSORCOG_POS_HIGH_LATCH under various speeds
  '     4. Adjust tach amplifier so that POS_HIGH_LATCH is stable
  '     5. Set TACH_RATIO to $10000 / POS_HIGH_LATCH
  '     6. Set CYCLE_INTR_LOW to SENSORCOG_POS_LOW_LATCH
  '     7. Measure the position at top/bottom and set CYCLE_TOP/CYCLE_BOTTOM
  
  CYCLE_INTR_HIGH  = $0000         ' Position when photointerrupter goes high
  CYCLE_INTR_LOW   = $5ac9         ' Position when it goes low
  TACH_RATIO       = $10000 / 172  ' Cycle fraction per tachometer pulse

  ' 16-bit shaft angle values. All values are modulo CYCLE_LEN.
  CYCLE_LEN        = $10000
  CYCLE_MASK       = $FFFF
  CYCLE_TOP        = 58000
  CYCLE_BOTTOM     = 25000

  CYCLE_THRESHOLD_COARSE  = 10000  ' "Close enough", don't have to move at all                             
  CYCLE_THRESHOLD_FINE    = 10000  ' When to coast before reaching target

  ' Sensor cog communications area
  SENSORCOG_TACH_COUNT     = 0   ' Tachometer pulse count
  SENSORCOG_POSITION       = 1   ' Shaft position estimate
  SENSORCOG_POS_HIGH_LATCH = 2   ' Latched position when intr goes high
  SENSORCOG_POS_LOW_LATCH  = 3   ' Latched position when intr goes low
  SENSORCOG_NUM            = 4

  ' Motion control modes
  MODE_IDLE            = 0       ' Motion control cog stops writing motor_speed
  MODE_OPENLOOP_SPEED  = 1       ' Open loop speed control with acceleration limit
  MODE_SERVO_SPEED     = 2       ' Servo speed control
  
  ' Motion control constants
  MOTION_LOOP_HZ       = 4000    ' Control loop frequency
  MOTION_MAX_ACCEL     = $200    ' Maximum acceleration per tick in open-loop mode.
                                 '   Larger values make us more responsive, but use more
                                 '   power and create more mechanical stress.
  MOTION_SERVO_GAIN    = $10000  ' This should be the highest value that doesn't cause oscillations
                                 
  ' Speeds for runToPosition()
  POSITIONING_SPEED_COARSE = $c000
  POSITIONING_SPEED_FINE   = $4000
                                 

VAR
  long  pwm_cog       
  long  motor_speed                ' Current motor speed (-$ff to +$ff), set by motion cog

  long  motion_mode                ' Motion control inputs
  long  motion_target_speed        ' Target speed (mode-specific)
  long  motion_current_speed       ' Current motor speed (24.8 fixed point PWM value)
  long  motion_current_tach        ' Current tachometer speed (RPM, in 16.16 fixed point) 
  
  long  sensorcog[SENSORCOG_NUM]   ' Sensor cog data

  long  motioncog_stack[32]

  byte  pedal_down                 ' Current binary up/down state for pedal
  
PUB start
  '' Initialize the SewingMachine object, and launch cogs:
  ''    - One cog for motor PWM
  ''    - One cog for monitoring sensors
  ''    - One cog for motor motion control

  pwmStart
  cognew(@sensorcog_entry, @sensorcog)
  cognew(motioncog, @motioncog_stack)

  ' Say hello!
  beep(1046, 80)
  beep(880, 80)


PUB readPedal : value
  '' Read the pedal position. Returns a normalized 16-bit value ($0000 to $ffff).
  value := (readPedalRaw - PEDAL_MIN <# 0) << 16 / constant(PEDAL_MAX - PEDAL_MIN) <# $FFFF
                                                                                
PUB readPedalRaw : value | timer
  '' Read the pedal position, returning a raw un-calibrated value. This is really only
  '' useful when you're debugging, or in trying to set PEDAL_MIN and PEDAL_MAX.

  ' This should be roughly equivalent to using the RCTIME module, but
  ' RCTIME seems to hang sometimes.

  dira[PIN_PEDAL]~~
  outa[PIN_PEDAL]~~              ' Charge capacitor
  waitcnt(cnt + clkfreq / 1000)
  dira[PIN_PEDAL]~               ' Start discharging
  timer := cnt                   ' Time it
  waitpeq(0, constant(|<PIN_PEDAL), INA)
  value := (cnt - timer) >> 5    ' Measure discharge time

PUB isPedalDown : value
  '' Read a binary up/down value for the pedal. This includes hysteresis,
  '' so the value won't oscillate when the pedal is in the middle of its range.

  if pedal_down
    value := pedal_down := readPedal > $7000
  else
    value := pedal_down := readPedal > $9000

PUB beep(freqHz, lenMs) | period, cycles, timer
  '' Stop the motor briefly, and use audible vibration in the motor
  '' to play a tone. This can be used for warning indicators or for debugging.

  pwmStop

  period := clkfreq / freqHz
  cycles := lenMs * freqHz / 1000
  timer := cnt

  outa[PIN_DIRECTION]~
  outa[PIN_PWM]~
  outa[PIN_BRAKE]~

  dira[PIN_DIRECTION]~~
  dira[PIN_PWM]~~
  dira[PIN_BRAKE]~~
  
  repeat cycles
    waitcnt(timer += period)
    outa[PIN_PWM]~~   ' Very short pulse. Longer is louder, but also more likely to actually turn the motor.
    outa[PIN_PWM]~~
    outa[PIN_PWM]~~
    outa[PIN_PWM]~

  pwmStart

PUB getPosition : pos
  '' Get an estimate of the machine's current cycle position

  pos := sensorcog[SENSORCOG_POSITION]

PUB getSpeed : speed
  '' Read the current speed of the sewing machine shaft.
  '' Returns revolutions per minute, in 16.16 fixed point.

  speed := motion_current_tach
       
PUB runToPosition(p) | milestone, dist
  '' Move forward to the given position.
  ''
  '' We'll speed up toward full speed until we reach 1/2 of the way toward the destination,
  '' then we start slowing down to low speed until we get within the threshold, then we stop.

  dist := ||(getPosition - p) & CYCLE_MASK
  if dist < CYCLE_THRESHOLD_COARSE
    ' Already close enough
    return

  milestone := ((p - getPosition) & CYCLE_MASK) >> 1
  
  repeat
    dist := (p - getPosition) & CYCLE_MASK

    if dist > milestone
      motorOpenLoopSpeed(POSITIONING_SPEED_COARSE)
    elseif dist > CYCLE_THRESHOLD_FINE
      motorOpenLoopSpeed(POSITIONING_SPEED_FINE)
    else
      motorOpenLoopSpeed(0)
      return

PUB motorOpenLoopSpeed(speed)
  '' Run the motor in open-loop speed control mode, and set the target speed.
  '' Speed is between -$ffff and $ffff.

  motion_target_speed := speed
  motion_mode := MODE_OPENLOOP_SPEED

PUB motorServoSpeed(speed)
  '' Run the motor in closed-loop servo speed control mode. The target
  '' speed is in RPM, encoded as 16.16 fixed point.

  motion_target_speed := speed
  motion_mode := MODE_SERVO_SPEED
   
PRI pwmStart
  ' Start the PWM cog, if it isn't already running

  if not pwm_cog
    motor_speed~
    pwm_cog := 1 + cognew(@pwmcog_entry, @motor_speed)

PRI pwmStop
  ' Stop the PWM cog, if it's running

  if pwm_cog
    cogstop(pwm_cog - 1)
    pwm_cog~

PRI motioncog | loop_period, loop_cnt, cur_tachcnt, prev_tachcnt, unfiltered_tach, xv0, xv1
  ' Main loop for motion cotrol cog. This cog runs one of several speed
  ' control algorithms, depending on the current mode.

  longfill(@loop_period, 0, 7)
  
  loop_period := clkfreq / MOTION_LOOP_HZ
  loop_cnt := cnt
  
  repeat
    waitcnt(loop_cnt += loop_period)

    ' Update the current tachometer reading, by sampling the
    ' sensor cog's counter and converting into fixed point RPM.
    '
    ' TACH_RATIO is in units of (revolution / tach pulse), in 16.16 FP.
    ' Our sampling rate is MOTION_LOOP_HZ Hz. So, to convert to RPM, we need:
    '
    '   tach * TACH_RATIO [rev/tach] * MOTION_LOOP_HZ [1/sec] * 60 [sec/min]
    '
    ' Tach pulses arrive relatively slowly compared to our motion loop's
    ' frequency, so we use a simple digital low-pass filter to smooth out
    ' the speed estimate.
    '
    ' This filter is a fixed-point version of a 1-pole low pass Butterworth
    ' filter designed with http://www-users.cs.york.ac.uk/~fisher/cgi-bin/mkfscript
    ' using a sampling rate of 1 kHz and a corner frequency of 10 Hz.
    
    prev_tachcnt := cur_tachcnt
    cur_tachcnt := sensorcog[SENSORCOG_TACH_COUNT]
    unfiltered_tach := (cur_tachcnt - prev_tachcnt) * constant(TACH_RATIO * MOTION_LOOP_HZ * 60)
    
    xv0 := xv1
    xv1 := unfiltered_tach ** $7ccccc0                                          ' FP division: unfiltered_tach / 3.282051595e+01
    motion_current_tach := xv0 + xv1 + (motion_current_tach ** $7833333f) << 1  ' FP mul: yv0 * 0.9390625058 
    
    ' Update the mode-specific state

    case motion_mode

      MODE_OPENLOOP_SPEED:
        if motion_current_speed < motion_target_speed
          motion_current_speed := motion_current_speed + MOTION_MAX_ACCEL <# motion_target_speed
        else
          motion_current_speed := motion_current_speed - MOTION_MAX_ACCEL #> motion_target_speed
        motor_speed := motion_current_speed >> 8

      MODE_SERVO_SPEED:
        motion_current_speed += MOTION_SERVO_GAIN ** (motion_target_speed - motion_current_tach)
        motion_current_speed #>= 0
        motor_speed := motion_current_speed >> 8
          

DAT

'==============================================================================
' PWM Motor Driver Cog
'==============================================================================

                        org
pwmcog_entry
                        ' Init pins
                        mov       dira, pwm_init_dira

                        ' Main PWM loop
:loop
                        add       pwm_counter, #1
                        and       pwm_counter, #$FF wz

                        ' At the top of each cycle, latch speed and direction
        if_nz           jmp       #:mid_cycle
                        rdlong    pwm_latch, par
                        shl       pwm_latch, #1 nr,wc   ' Test sign
        if_c            neg       pwm_latch, pwm_latch  ' Absolute value      
                        muxnc     outa, dir_pin_mask    ' Set direction pin 
:mid_cycle
                        cmp       pwm_counter, pwm_latch wc
                        muxc      outa, pwm_pin_mask
                
                        jmp       #:loop

pwm_init_dira long      |<PIN_DIRECTION | |<PIN_PWM | |<PIN_BRAKE
pwm_pin_mask  long      |<PIN_PWM
dir_pin_mask  long      |<PIN_DIRECTION
pwm_counter   long      0       ' Current point in PWM cycle
pwm_latch     long      0       ' Latched copy of PWM parameter

                        fit


'==============================================================================
' Sensor Cog
'==============================================================================

                        org
sensorcog_entry

:loop
                        ' Sample inputs
                        test    intr_pin_mask, ina wc
                        rcl     intr_shift, #1
                        test    tach_pin_mask, ina wc
                        rcl     tach_shift, #1

                        ' Count tachometer edges
                        cmp     tach_shift, pos_edge wz
              if_z      add     tach_count, #1
              if_z      add     position, c_tach_ratio

                        ' Position reference using photointerrupter
                        cmp     intr_shift, neg_edge wz
              if_z      mov     pos_lat_low, position
              if_z      mov     position, c_cycle_low      ' Disable for calibration
                        cmp     intr_shift, pos_edge wz
              if_z      mov     pos_lat_high, position
              if_z      mov     position, c_cycle_high
:no_intr
              
                        ' Write back state
                        mov     t1, par
                        wrlong  tach_count, t1
                        add     t1, #4
                        wrlong  position, t1
                        add     t1, #4
                        wrlong  pos_lat_high, t1
                        add     t1, #4
                        wrlong  pos_lat_low, t1
                        
                        jmp     #:loop

intr_pin_mask long      |<PIN_INTERRUPTER
tach_pin_mask long      |<PIN_TACHOMETER
intr_shift    long      0
tach_shift    long      0

pos_edge      long      $7FFFFFFF
neg_edge      long      $80000000

c_tach_ratio  long      TACH_RATIO
c_cycle_low   long      CYCLE_INTR_LOW
c_cycle_high  long      CYCLE_INTR_HIGH

tach_count    long      0
position      long      0
pos_lat_high  long      0
pos_lat_low   long      0
                                             
t1            res       1

                        fit

                    
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}