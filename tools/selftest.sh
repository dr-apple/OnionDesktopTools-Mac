#!/bin/zsh
# Runs the in-app self-test on a pretend SD card in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/local.onion.desktoptools.savedState
rm -rf /tmp/odt-self /tmp/odt-self-card /tmp/odt-self-card-restore
mkdir -p /tmp/odt-self-card
APP_STORE=/tmp/odt-self APP_FAKE_CARD=/tmp/odt-self-card ~/Applications/OnionDesktopTools.app/Contents/MacOS/OnionDesktopTools --selftest
