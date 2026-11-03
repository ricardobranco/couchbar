.PHONY: build test app run install clean icon release

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

icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	for size in 16 32 128 256 512; do \
		swift scripts/make-icon.swift build/AppIcon.iconset/icon_$${size}x$${size}.png $$size; \
		swift scripts/make-icon.swift build/AppIcon.iconset/icon_$${size}x$${size}@2x.png $$((size * 2)); \
	done
	iconutil -c icns build/AppIcon.iconset -o Support/AppIcon.icns
	swift scripts/make-icon.swift docs/icon.png 256

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)

release:
	ARCHS="arm64 x86_64" ./scripts/build-app.sh
	mkdir -p dist
	ditto -c -k --keepParent "build/Couchbar.app" "dist/Couchbar-$(VERSION).zip"
	shasum -a 256 "dist/Couchbar-$(VERSION).zip"
