#!/bin/zsh
# Snapshots of every page in light and dark, with a pretend Onion SD card in /tmp.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=install,settings tools/snap.sh
set -u
app=~/Applications/OnionDesktopTools.app/Contents/MacOS/OnionDesktopTools
shots=/tmp/OnionDesktopTools-shots
rm -rf ~/Library/Saved\ Application\ State/local.onion.desktoptools.savedState
rm -rf /tmp/odt-snap /tmp/odt-snap-card $shots
mkdir -p /tmp/odt-snap-card
APP_STORE=/tmp/odt-snap APP_FAKE_CARD=/tmp/odt-snap-card APP_SNAPSHOT=$shots $app
