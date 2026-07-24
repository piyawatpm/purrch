# Builds the .app bundle. SwiftPM produces a bare executable plus a resource
# bundle; this assembles both into something Finder and launchd will accept.
#
#   make          build + assemble into ./Purrch.app
#   make run      build and launch it
#   make art      regenerate sprite sheets and sounds
#   make install  copy into /Applications
#
# Rename the app by overriding APP_NAME, e.g.  make APP_NAME=Mochi
# Default is Purrch. The cat's own name is a separate in-app setting.

APP_NAME ?= Purrch
APP      := $(APP_NAME).app
BIN      := .build/release/PetApp
RESBUNDLE:= .build/release/DeskPet_PetApp.bundle
CONTENTS := $(APP)/Contents

.PHONY: all build bundle run art install clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BIN)" "$(CONTENTS)/MacOS/$(APP_NAME)"
	cp -R "$(RESBUNDLE)" "$(CONTENTS)/Resources/"
	sed 's/APP_NAME/$(APP_NAME)/g' Info.plist > "$(CONTENTS)/Info.plist"
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"; fi
	# Ad-hoc signature: enough for local use and for launch-at-login to register.
	codesign --force --sign - --timestamp=none "$(APP)" >/dev/null 2>&1 || true
	@echo "built $(APP)"

run: bundle
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	open "$(APP)"

art:
	python3 tools/spritegen.py
	python3 tools/soundgen.py
	python3 tools/iconogen.py

install: bundle
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	rm -rf "/Applications/$(APP)"
	cp -R "$(APP)" /Applications/
	@echo "installed to /Applications/$(APP)"

clean:
	rm -rf .build "$(APP)"
