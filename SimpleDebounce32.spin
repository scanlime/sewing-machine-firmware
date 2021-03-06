{{

SimpleDebounce32 
----------------

This is a super-simple button debouncer, for all pins, which
tries not to suck. One way in which a button debouncer can suck
is to waste an entire cog! So we don't do that :)

This expects that the buttons will be periodically sampled at
a reasonable rate in the milliseconds or tens of milliseconds
range. We keep the last three samples, and look for a pattern:
The button was up, then it was down for two consecutive samples.
If we see this, record a press.

Currently this assumes active-low buttons.

┌──────────────────────────────┐
│ Micah Elizabeth Scott        │               
│ This file is public domain.  │               
└──────────────────────────────┘

}}

VAR
  long  states[3]

PUB start
  ' Initialize the sample buffer

  repeat 3
    sample
  
PUB sample
  ' Sample, and shift out older readings
  states[0] := states[1]
  states[1] := states[2]
  states[2] := !ina

  ' Look for the pattern ("011")
  states[0] := states[2] & states[1] & !states[0]

PUB pressed(num)
  ' Was button 'num' just now pressed?

  return 1 & (states[0] >> num)
