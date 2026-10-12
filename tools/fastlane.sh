#!/bin/zsh
# Runs fastlane for the App Store listing with the right Ruby and settings.
#
#   tools/fastlane.sh metadata            upload listing text (no binary, no submit)
#   tools/fastlane.sh promo_text          upload promotional text only
#   tools/fastlane.sh screenshots         upload the framed iPhone + iPad screenshots
#   tools/fastlane.sh download_metadata   pull the live listing into fastlane/metadata
#
# macOS's built-in Ruby (2.6) is too old for current fastlane, so this uses
# Homebrew's Ruby. Gems live in vendor/bundle (git-ignored), installed on
# first run from Gemfile.lock, so everyone gets the exact same fastlane.
set -euo pipefail
cd "${0:A:h:h}"

RUBY_BIN=/opt/homebrew/opt/ruby/bin
[[ -x "$RUBY_BIN/ruby" ]] || { echo "Needs Homebrew Ruby: brew install ruby" >&2; exit 1; }
export PATH="$RUBY_BIN:$PATH"
export BUNDLE_PATH=vendor/bundle
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # fastlane warns without a UTF-8 locale
export FASTLANE_OPT_OUT_USAGE=YES            # no usage statistics sent to fastlane
export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1
export FASTLANE_SKIP_DOCS=1                  # keep our own fastlane/README.md

# The API key settings, kept outside the repo (see fastlane/README.md).
[[ -f ~/.appstoreconnect/archipic.env ]] && source ~/.appstoreconnect/archipic.env

bundle check >/dev/null 2>&1 || bundle install --quiet
exec bundle exec fastlane "$@"
