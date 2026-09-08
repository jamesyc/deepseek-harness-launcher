#!/bin/bash
set -euo pipefail

launcher_app='/Users/jameschang/Applications/DeepSeek Harness Launcher.app'

test -d "$launcher_app"
plutil -lint "$launcher_app/Contents/Info.plist"
test "$(plutil -extract LSUIElement raw "$launcher_app/Contents/Info.plist")" = true
osadecompile "$launcher_app" | rg -q 'mise exec -- dsh web --no-open'
osadecompile "$launcher_app" | rg -q 'kill -TERM'
osadecompile "$launcher_app" | rg -q 'Chrome Apps.localized/DeepSeek Harness.app'
test -f "$launcher_app/Contents/Resources/applet.icns"

echo 'launcher bundle verified'
