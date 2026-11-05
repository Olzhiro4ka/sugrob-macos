SWIFT_FLAGS := -Xswiftc -warnings-as-errors
APP := build/Sugrob.app
ARGS ?=

.PHONY: build test run app dmg clean

build:
	swift build -c debug $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS)

run:
	-pkill -x Sugrob
	scripts/bundle.sh debug
	open -n $(APP) $(if $(strip $(ARGS)),--args $(ARGS))

app:
	scripts/bundle.sh release --universal

dmg: app
	scripts/make_dmg.sh

clean:
	swift package clean
	rm -rf .build build
