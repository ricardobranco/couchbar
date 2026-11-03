.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "build/Couchbar.app"

install: app
	rm -rf "/Applications/Couchbar.app"
	cp -R "build/Couchbar.app" /Applications/

clean:
	rm -rf .build build
