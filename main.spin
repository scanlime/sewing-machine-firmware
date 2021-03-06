{{

Sewing Machine -- Interactive main program
------------------------------------------

This is a top-level object for controlling the sewing machine
interactively using the LCD and encoder wheel.

┌──────────────────────────────────────────┐
│ Copyright (c) 2010 Micah Elizabeth Scott │               
│     See end of file for terms of use.    │               
└──────────────────────────────────────────┘

}}

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  ' UI Pins
  BTN_ENTER       = 4
  PIN_ENCODER0    = 5
  PIN_ENCODER1    = 6
  PIN_LEDS        = 7
  LCD_RESET       = 10
  LCD_DATA        = 11
  LCD_CLOCK       = 12
  LCD_CS          = 13
  BTN_S2          = 14
  BTN_S1          = 15

  LED_OFF         = %000
  LED_RED         = %001
  LED_GREEN       = %100
  LED_BLUE        = %010
  LED_WHITE       = %111

  ' Encoder delta that we count as one 'click'
  WHEEL_STEPSIZE = 4

  ' Maximum RPM we'll shoot for in servo mode
  MAX_RPM = 400

  ' Sewing modes
  #0, MODE_OPENLOOP, MODE_STOPUP, MODE_STOPDOWN, MODE_SERVO, MODE_UPDOWN, MODE_OFF, NUM_MODES

  ' UI Hilight types
  #0, HI_TOPLEVEL, HI_MODE

  ' Top-level hilights
  #0, TOP_MODE, TOP_STITCH, NUM_TOPLEVEL


DAT

modeNames     byte "Open Loop ", 0,0,0,0,0,0
              byte "Stop ↑Up  ", 0,0,0,0,0,0
              byte "Stop ↓Down", 0,0,0,0,0,0
              byte "Servo     ", 0,0,0,0,0,0
              byte "Up/Down ↑↓", 0,0,0,0,0,0
              byte "(Off)     ", 0,0,0,0,0,0
              

OBJ
  sew : "SewingMachine"
  lcd : "Nokia6100"
  num : "Simple_Numbers"
  encoder : "Quadrature Encoder"
  btn : "SimpleDebounce32"
  fm : "FloatMath"
  
VAR
  long  wheelRaw[2]
  long  rpmX0, rpmX1, rpmY0, rpmY1
  long  rpmNext, rpmPeriod
  long  rand
  long  cuteWalkPos, cuteWalkSpeed
  
  ' Current UI inputs
  long  pedal, wheel

  ' Current UI state
  byte  statusColor
  long  mode, hilight, topLevel


PUB start

  setLED(LED_RED)               ' Busy initializing
  btn.start                     ' Read the initial button samples
  sew.start                     ' Start sewing machine controller

  encoder.start(PIN_ENCODER0, 1, 0, @wheelRaw)
  
  initLCD

  ' Defaults
  mode := MODE_SERVO
  
  ' Set up the periodic RPM rate refresh
  rpmPeriod := clkfreq / 5
  rpmNext := cnt
 
  ' All systems go!
  setLED(statusColor := LED_GREEN)
  
  mainLoop

PRI initLCD
  lcd.start(LCD_RESET, LCD_DATA, LCD_CLOCK, LCD_CS, lcd#EPSON)
  lcd.background(lcd#BLUE)
  lcd.color(lcd#WHITE)
  lcd.clear

PRI mainLoop
  repeat
    btn.sample
    readWheelSteps

    handleButtons
    drawMenus
    drawInstruments

    if hilight == HI_MODE
      ' Editing the mode- machine is not operating
      setLED(statusColor := LED_RED)
    else
      ' Operating normally
      setLED(statusColor := LED_GREEN)
      sewControl


PRI sewControl | prevPedal
  ' Run the sewing machine, according to the current mode

  prevPedal := pedal
  
  case mode

    MODE_OPENLOOP:
      pedal := sew.readPedal
      sew.motorOpenLoopSpeed(pedal)

    MODE_STOPUP:
      pedal := sew.readPedal
      if pedal
        sew.motorOpenLoopSpeed(pedal)
      else        
        sew.runToPosition(sew#CYCLE_TOP)
  
    MODE_STOPDOWN:
      pedal := sew.readPedal
      if pedal
        sew.motorOpenLoopSpeed(pedal)
      else        
        sew.runToPosition(sew#CYCLE_BOTTOM)

    MODE_SERVO:
      pedal := sew.readPedal
      sew.motorServoSpeed(pedal * MAX_RPM)

    MODE_UPDOWN:
      pedal := $FFFF & sew.isPedalDown

      ' Only call runToPosition when the pedal state changes-
      ' we don't want the motor to run spontaneously if there's
      ' a sensor glitch but the pedal wasn't touched.
      if pedal and not prevPedal
        sew.runToPosition(sew#CYCLE_BOTTOM)
      if prevPedal and not pedal
        sew.runToPosition(sew#CYCLE_TOP)

    MODE_OFF:
      pedal := sew.readPedal
      sew.motorOpenLoopSpeed(0)

        
PRI handleButtons | enter

  ' The two tiny buttons are rather inconvenient to use for normal
  ' UI interactions, so right now I'm using them for special functions
  ' that I may want for debugging problems.

  ' Soft reboot button
  if btn.pressed(BTN_S2)
    reboot

  ' LCD Reset button
  if btn.pressed(BTN_S1)
    lcd.stop
    initLCD

  ' Different actions depending on our hilight type...
  case hilight

    HI_TOPLEVEL:
      wheelValue(@topLevel, NUM_TOPLEVEL)
      if btn.pressed(BTN_ENTER)
        case topLevel

          TOP_MODE:
            enterFeedback
            hilight := HI_MODE

          TOP_STITCH:
            enterFeedback
            sew.runToPosition(sew#CYCLE_BOTTOM)              
            sew.runToPosition(sew#CYCLE_TOP)              
            
    HI_MODE:
      wheelValue(@mode, NUM_MODES)
      if btn.pressed(BTN_ENTER)
        enterFeedback      
        hilight := HI_TOPLEVEL


PRI drawMenus | visibleMode
  ' Draw menus (things that are editable)

  colorLabel(hilight == HI_TOPLEVEL and topLevel == TOP_MODE)
  lcd.text(2, 2, string("Mode:"))
  colorNormal(hilight == HI_MODE)
  lcd.text(45, 2, @modeNames + (mode << 4))

  colorLabel(hilight == HI_TOPLEVEL and toplevel == TOP_STITCH)
  lcd.text(2, 20, string("Single Stitch"))
   

PRI readWheelSteps
  ' Sample the control wheel motion. Return the number of positive clockwise
  ' steps or negative anticlockwise steps.

  wheel := (wheelRaw[1] - wheelRaw[0]) / WHEEL_STEPSIZE
  wheelRaw[1] -= wheel * WHEEL_STEPSIZE

PRI filterRPM
  ' This is a more aggressive low-pass filter for the RPM estimate,
  ' so it holds still enough we can actually read it.

  rpmX0 := rpmX1
  rpmX1 := fm.FMul(fm.FFloat(sew.getSpeed >> 16), constant(1.0 / 5.70463))
  rpmY0 := rpmY1
  rpmY1 := fm.FAdd(fm.FAdd(rpmX0, rpmX1), fm.FMul(rpmY0, 0.649408))

  return fm.FRound(rpmY1)
  
PRI setLED(color)
  ' Change the LED color. Takes an LED_* constant.

  dira := (dira & constant(!(LED_WHITE << PIN_LEDS))) | (color << PIN_LEDS)

PRI enterFeedback
  ' Enter button audiovisual feedback: chirp and flash
  setLED(LED_WHITE)
  sew.beep(1200, 30)
  setLED(statusColor)

PRI wheelFeedback
  ' Wheel audiovisual feedback: click and flash
  setLED(LED_WHITE)
  sew.beep(800, 10)
  setLED(statusColor)

PRI wheelValue(valPtr, numValues) | prev, new
  ' Update a value according to wheel motion.
  ' Clamps against 0 and numValues-1. Feedback only if we changed the value.

  prev := LONG[valPtr]
  new := (prev + wheel) #> 0 <# (numValues - 1)
  if new <> prev
    LONG[valPtr] := new
    wheelFeedback  

PRI lcdBargraph(x, y, w, h, value)
  ' Display a proportional reading from $0000 to $ffff, on a bargraph display.
  ' Uses the current foreground color. (The color is, however, changed during
  ' this function call.)

  ' Scale to pixels
  value := (value * (w - 2) + $7FFF) >> 16

  ' Filled portion
  lcd.box(x+1, y+1, value, h-2)

  ' Empty portion
  lcd.color(lcd#BLACK)
  lcd.box(x+1+value, y+1, w-2-value, h-2)
  
  ' Outline
  lcd.color(lcd#WHITE)
  lcd.box(x, y, w, 1)
  lcd.box(x, y+h-1, w, 1)
  lcd.box(x, y, 1, h)
  lcd.box(x+w-1, y, 1, h)

PRI colorNormal(showHilight)
  ' Normal text colors
  if showHilight
    lcd.color(lcd#BLUE)
    lcd.background(lcd#WHITE)
  else
    lcd.color(lcd#WHITE)
    lcd.background(lcd#BLUE)

PRI colorLabel(showHilight)
  ' Text colors for a label
  if showHilight
    lcd.color(lcd#BLUE)
    lcd.background(lcd#YELLOW)
  else
    lcd.color(lcd#YELLOW)
    lcd.background(lcd#BLUE)


PRI drawInstruments | rpm
  ' Draw doodads on the screen which show our current status

  ' Machine speed
  ' (Update infrequently, otherwise it changes too fast to read)
  if (cnt - rpmNext) > 0
    rpmNext += rpmPeriod
    rpm := filterRPM
    colorNormal(0)
    lcd.text(2, 95, num.decf(rpm, 6))
    colorLabel(0)
    lcd.text(58, 95, string("RPM"))

    ' Text is boring, also graphically represent speed with a cute sprite
    if rpm
      cuteWalkSpeed := rpm * CUTENESS_WALK_SPEED
    else
      ' Not walking. Do the sleepy animation...
      cuteWalkSpeed~
      if (?rand & %1111) == 0
        cutenessFrame(CUTENESS_SLEEPY)
      else
        cutenessFrame(CUTENESS_IDLE)

  ' Animate the cute sprite every frame
  if cuteWalkSpeed
    cuteWalkPos += cuteWalkSpeed
    if cuteWalkPos => CUTENESS_WALK_LEN
      cuteWalkPos -= CUTENESS_WALK_LEN
    cutenessFrame(cuteness_walk[cuteWalkPos >> 16])
      
  ' Pedal graph
  lcd.color($F40)
  lcdBargraph(0, 112, lcd#WIDTH, 8, pedal)

  ' Machine position graph
  lcd.color(lcd#YELLOW)
  lcdBargraph(0, 122, lcd#WIDTH, 8, $FFFF & sew.getPosition)  
    
PRI cutenessFrame(i)
  ' Draw our cute sprite, at frame #i
  lcd.image(93, 86, 26, 24, @cuteness_sprite + 936*i)

CON                                                   
  CUTENESS_IDLE   = 0
  CUTENESS_SLEEPY = 1

  CUTENESS_WALK_LEN   = 6 << 16
  CUTENESS_WALK_SPEED = 150

DAT
  cuteness_sprite       file "sprite_kirby.bin"
  cuteness_walk         byte 2, 3, 4, 5, 4, 3
    
  
DAT
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
