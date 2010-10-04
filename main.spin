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
  #0, MODE_OPENLOOP, MODE_STOPDOWN, MODE_SERVO, MODE_UPDOWN, NUM_MODES

  ' UI Hilight types
  #0, HI_TOPLEVEL, HI_MODE

  ' Top-level hilights
  #0, TOP_MODE, NUM_TOPLEVEL


DAT

modeNames     byte "Open Loop ", 0,0,0,0,0,0
              byte "Stop Down ", 0,0,0,0,0,0
              byte "Servo     ", 0,0,0,0,0,0
              byte "Up/Down   ", 0,0,0,0,0,0

OBJ
  sew : "SewingMachine"
  lcd : "Nokia6100"
  num : "Simple_Numbers"
  encoder : "Quadrature Encoder"
  btn : "SimpleDebounce32"
  
VAR
  long  wheelRaw[2]

  ' Current UI inputs
  long  pedal, wheel

  ' Current UI state
  byte  mode, statusColor, hilight, topLevel


PUB start

  setLED(LED_RED)               ' Busy initializing
  btn.start                     ' Read the initial button samples
  sew.start                     ' Start sewing machine controller

  encoder.start(PIN_ENCODER0, 1, 0, @wheelRaw)
  
  lcd.start(LCD_RESET, LCD_DATA, LCD_CLOCK, LCD_CS, lcd#EPSON)
  lcd.background(lcd#BLUE)
  lcd.color(lcd#WHITE)
  lcd.clear

  ' All systems go!
  setLED(statusColor := LED_GREEN)
  
  mainLoop


PRI mainLoop
  repeat
    btn.sample
    wheel := readWheelSteps

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

        
PRI handleButtons | enter

  ' Soft reboot button
  if btn.pressed(BTN_S2)
    reboot

  ' "Enter" button
  if enter := btn.pressed(BTN_ENTER)
    ' Audiovisual feedback: click and flash
    setLED(LED_BLUE)
    sew.beep(1200, 30)
    setLED(statusColor)

  ' Different actions depending on our hilight type...

  case hilight

    HI_TOPLEVEL:
      topLevel := (topLevel + wheel) // NUM_TOPLEVEL
      if enter
        case topLevel
          TOP_MODE:  hilight := HI_MODE

    HI_MODE:
      mode := (mode + wheel) // NUM_MODES
      if enter
        hilight := HI_TOPLEVEL      


PRI drawMenus | visibleMode
  ' Draw menus (things that are editable)

  colorLabel(hilight == HI_TOPLEVEL and topLevel == TOP_MODE)
  lcd.text(2, 2, string("Mode:"))
  colorNormal(hilight == HI_MODE)
  lcd.text(45, 2, @modeNames + (mode << 4))
   

PRI drawInstruments | rpm
  ' Draw doodads on the screen which show our current status

  ' Machine speed
  colorNormal(0)
  rpm := sew.getSpeed >> 16
  if rpm <> $FFFF
    lcd.text(2, 95, num.decf(rpm, 6))
  colorLabel(0)
  lcd.text(58, 95, string("RPM"))
  
  ' Pedal graph
  lcd.color($F40)
  lcdBargraph(0, 112, lcd#WIDTH, 8, pedal)

  ' Machine position graph
  lcd.color(lcd#YELLOW)
  lcdBargraph(0, 122, lcd#WIDTH, 8, sew.getPosition)


PRI readWheelSteps
  ' Sample the control wheel motion. Return the number of positive clockwise
  ' steps or negative anticlockwise steps.

  result := (wheelRaw[1] - wheelRaw[0]) / WHEEL_STEPSIZE
  wheelRaw[1] -= result * WHEEL_STEPSIZE

  if result
    ' Audiovisual feedback: click and flash
    setLED(LED_WHITE)
    sew.beep(800, 10)
    setLED(statusColor)

  
PRI setLED(color)
  ' Change the LED color. Takes an LED_* constant.

  dira := (dira & constant(!(LED_WHITE << PIN_LEDS))) | (color << PIN_LEDS)


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