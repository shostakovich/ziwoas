#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Brings a remote container to the point where bin/rubocop, bin/rails test and
# bin/ci run unattended: Ruby 4.0.7 on PATH, gems installed, a device config in
# place and the SQLite databases prepared.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

RBENV_ROOT="${RBENV_ROOT:-/opt/rbenv}"
RUBY_VERSION="$(cat .ruby-version)"
TOOLCACHE="/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64"

# The prebuilt Ruby is unpacked one level too deep (…/x64/x64). Both the
# interpreter's rpath and every gem shebang point at the outer path, so ruby
# cannot find libruby.so and `gem`/`bundle` fail with "required file not found".
# Flattening the directory repairs rbenv's 4.x version in place.
if [ ! -x "${TOOLCACHE}/bin/ruby" ] && [ -x "${TOOLCACHE}/x64/bin/ruby" ]; then
  echo "== Repairing Ruby ${RUBY_VERSION} toolcache layout =="
  mv "${TOOLCACHE}/x64"/* "${TOOLCACHE}/"
  rmdir "${TOOLCACHE}/x64"
fi

# Non-login shells start on the system Ruby; the shims pick up .ruby-version.
export PATH="${RBENV_ROOT}/shims:${RBENV_ROOT}/bin:${PATH}"
rbenv rehash
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${RBENV_ROOT}/shims:${RBENV_ROOT}/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE}"
fi
echo "== Ruby: $(ruby -v) =="

# config/ziwoas.yml is gitignored and holds device credentials. The test config
# describes the same shape with fixture values and talks to no real device.
if [ ! -f config/ziwoas.yml ]; then
  echo "== Seeding config/ziwoas.yml from config/ziwoas.test.yml =="
  cp config/ziwoas.test.yml config/ziwoas.yml
fi

echo "== Installing gems =="
bundle check || bundle install --jobs 4 --retry 3

# System tests drive Chrome through Cuprite and look for a Playwright browser
# under ~/.cache/ms-playwright; the remote container keeps one elsewhere.
CHROME="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}/chromium"
if [ -x "${CHROME}" ]; then
  export CUPRITE_CHROME_PATH="${CHROME}"
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export CUPRITE_CHROME_PATH=\"${CHROME}\"" >> "${CLAUDE_ENV_FILE}"
  fi
fi

echo "== Preparing databases =="
bin/rails db:prepare
RAILS_ENV=test bin/rails db:test:prepare

echo "== Setup complete =="
