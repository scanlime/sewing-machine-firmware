CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

OBJ
  term : "Parallax Serial Terminal"
  sew : "SewingMachine"

PUB main | pedal

  sew.start
  term.start(115200)

  repeat
    term.Str(String(term#NL, "Pedal Raw: "))
    term.Dec(sew.readPedalRaw)

    term.Str(String(" Converted: "))
    term.Dec(sew.readPedal)

    waitcnt(cnt + clkfreq/4)
  
    