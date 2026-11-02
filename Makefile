.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "build/TV Companion.app"

install: app
	rm -rf "/Applications/TV Companion.app"
	cp -R "build/TV Companion.app" /Applications/

clean:
	rm -rf .build build
