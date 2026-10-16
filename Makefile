# Comandos habituales de Baúl. Requiere Xcode 27, xcodegen y swiftlint (brew install xcodegen swiftlint).

DERIVED := build
APP_DEBUG := $(DERIVED)/Build/Products/Debug/Baul.app
APP_RELEASE := $(DERIVED)/Build/Products/Release/Baul.app

.PHONY: project build run test lint format install clean

project:  ## Genera Baul.xcodeproj a partir de project.yml
	xcodegen generate --quiet

build: project  ## Compila en Debug
	xcodebuild -project Baul.xcodeproj -scheme Baul -configuration Debug \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build -quiet

run: build  ## Compila y abre la app (cierra la instancia anterior)
	-pkill -x Baul
	open $(APP_DEBUG)

test:  ## Pruebas del paquete BaulKit
	cd Packages/BaulKit && swift test

lint:  ## SwiftLint sobre todo el código
	swiftlint lint --quiet

format:  ## Formatea con swift-format (incluido en Xcode)
	xcrun swift-format format --in-place --recursive App/Sources Packages/BaulKit/Sources Packages/BaulKit/Tests

install: project  ## Compila en Release e instala en /Applications
	xcodebuild -project Baul.xcodeproj -scheme Baul -configuration Release \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build -quiet
	-pkill -x Baul
	rm -rf /Applications/Baul.app
	cp -R $(APP_RELEASE) /Applications/Baul.app
	open /Applications/Baul.app

clean:
	rm -rf $(DERIVED) Baul.xcodeproj Packages/BaulKit/.build
