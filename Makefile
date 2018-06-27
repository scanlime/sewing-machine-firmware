OPENSPIN = /Applications/PropellerIDE.app/Contents/MacOS/openspin
LIBRARY = /Applications/PropellerIDE.app/Contents/Resources/library/library

BINARIES = \
	main.binary \
	mode_openloop.binary \
	mode_openloop_needledown.binary \
	mode_servo.binary \
	mode_updown.binary \

all: $(BINARIES)
.PHONY: all

%.binary: %.spin
	$(OPENSPIN) -L $(LIBRARY) $<

.PHONY: clean
clean:
	rm -f $(BINARIES)