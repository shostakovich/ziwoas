#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Brings a remote container to the point where bin/rubocop, bin/rails test and
# bin/ci run unattended: Ruby from .ruby-version on PATH, gems installed, a
# device config in place and the SQLite databases prepared. Before that,
# Erlang/OTP and Elixir for elixir/ — first, so a Ruby hiccup does not leave the
# container without them; a failure there warns without stopping the Ruby setup.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# The Phoenix app in elixir/ (issue #158) needs Erlang/OTP and Elixir. A failure
# there (e.g. no network to builds.hex.pm) only warns: the Ruby setup below runs
# regardless.
setup_elixir() {
  # Both come precompiled from builds.hex.pm (or the mirror in $HEX_BUILDS_URL, as for
  # Hex itself); versions are pinned once, in elixir/.tool-versions, which
  # erlef/setup-beam reads in GitHub Actions as well.
  BUILDS_URL="${HEX_BUILDS_URL:-https://builds.hex.pm}"
  ERLANG_VERSION="$(awk '$1 == "erlang" { print $2 }' elixir/.tool-versions)"
  ELIXIR_VERSION="$(awk '$1 == "elixir" { print $2 }' elixir/.tool-versions)"
  ERLANG_ROOT="/opt/erlang/${ERLANG_VERSION}"
  ELIXIR_ROOT="/opt/elixir/${ELIXIR_VERSION}"

  # A root counts as installed only once its marker exists, so an aborted download
  # never leaves a half-unpacked toolchain that later runs accept.
  if [ ! -f "${ERLANG_ROOT}/.installed" ]; then
    echo "== Installing Erlang/OTP ${ERLANG_VERSION} =="
    . /etc/os-release
    rm -rf "${ERLANG_ROOT}" && mkdir -p "${ERLANG_ROOT}"
    curl -fsSL --retry 3 "${BUILDS_URL}/builds/otp/${ID}-${VERSION_ID}/OTP-${ERLANG_VERSION}.tar.gz" \
      | tar -xz -C "${ERLANG_ROOT}" --strip-components=1
    (cd "${ERLANG_ROOT}" && ./Install -minimal "${ERLANG_ROOT}" > /dev/null)
    touch "${ERLANG_ROOT}/.installed"
  fi

  if [ ! -f "${ELIXIR_ROOT}/.installed" ]; then
    echo "== Installing Elixir ${ELIXIR_VERSION} =="
    ELIXIR_ZIP="$(mktemp --suffix=.zip)"
    curl -fsSL --retry 3 -o "${ELIXIR_ZIP}" "${BUILDS_URL}/builds/elixir/v${ELIXIR_VERSION}.zip"
    rm -rf "${ELIXIR_ROOT}" && mkdir -p "${ELIXIR_ROOT}"
    unzip -q "${ELIXIR_ZIP}" -d "${ELIXIR_ROOT}"
    rm -f "${ELIXIR_ZIP}"
    touch "${ELIXIR_ROOT}/.installed"
  fi

  # Without a UTF-8 locale the VM falls back to latin1 file names and Elixir warns
  # on every start.
  export PATH="${ELIXIR_ROOT}/bin:${ERLANG_ROOT}/bin:${PATH}"
  export LANG="${LANG:-C.UTF-8}"
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"${ELIXIR_ROOT}/bin:${ERLANG_ROOT}/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE}"
    echo "export LANG=\"${LANG}\"" >> "${CLAUDE_ENV_FILE}"
  fi
  echo "== Elixir: $(elixir --short-version) on OTP $(erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().') =="

  # HEX_CACERTS_PATH (set by the container) lets Hex trust the egress proxy.
  mix local.hex --force --if-missing > /dev/null
  mix local.rebar --force --if-missing > /dev/null

  echo "== Fetching and compiling Elixir deps =="
  (cd elixir && mix deps.get > /dev/null && MIX_ENV=test mix deps.compile > /dev/null)
}

# A child shell with its own errexit: bash ignores `set -e` inside a function
# called from `if`, so a failed download would otherwise run on.
if ! bash -euo pipefail -c "$(declare -f setup_elixir); setup_elixir"; then
  echo "WARNING: Elixir setup failed; elixir/ (mix test, script/golden_master) is unavailable this session." >&2
fi

# rbenv lives in /opt/rbenv in the cloud image, in ~/.rbenv elsewhere.
if [ -z "${RBENV_ROOT:-}" ]; then
  if command -v rbenv > /dev/null; then
    RBENV_ROOT="$(rbenv root)"
  elif [ -d /opt/rbenv ]; then
    RBENV_ROOT="/opt/rbenv"
  else
    RBENV_ROOT="${HOME}/.rbenv"
  fi
fi
# Empty when .ruby-version is missing: the image's own Ruby is used then.
RUBY_VERSION="$(cat .ruby-version 2>/dev/null || true)"

# The prebuilt Ruby is unpacked one level too deep (…/x64/x64). Both the
# interpreter's rpath and every gem shebang point at the outer path, so ruby
# cannot find libruby.so and `gem`/`bundle` fail with "required file not found".
# Flattening the directory repairs rbenv's 4.x version in place.
repair_toolcache_layout() {
  local toolcache="/opt/hostedtoolcache/Ruby/$1/x64"
  if [ ! -x "${toolcache}/bin/ruby" ] && [ -x "${toolcache}/x64/bin/ruby" ]; then
    echo "== Repairing Ruby $1 toolcache layout =="
    mv "${toolcache}/x64"/* "${toolcache}/"
    rmdir "${toolcache}/x64"
  fi
}

# Non-login shells start on the system Ruby; the shims pick up .ruby-version.
export RBENV_ROOT
export PATH="${RBENV_ROOT}/shims:${RBENV_ROOT}/bin:${PATH}"

if [ -z "${RUBY_VERSION}" ]; then
  echo "== No .ruby-version, using the image's Ruby =="
else
  repair_toolcache_layout "${RUBY_VERSION}"

  # The image ships an older 4.0.x than .ruby-version asks for. Refresh ruby-build's
  # definitions (a stale checkout does not know the new patch release) and compile
  # the missing version; -s makes this a no-op once it exists. Compiling takes minutes.
  if ! rbenv versions --bare | grep -qxF "${RUBY_VERSION}"; then
    echo "== Installing Ruby ${RUBY_VERSION} =="
    RUBY_BUILD_DIR="${RBENV_ROOT}/plugins/ruby-build"
    if [ -d "${RUBY_BUILD_DIR}/.git" ]; then
      git -C "${RUBY_BUILD_DIR}" pull --ff-only --quiet || true
    fi
    RUBY_BUILD_LOG="$(mktemp)"
    if rbenv install -s "${RUBY_VERSION}" > "${RUBY_BUILD_LOG}" 2>&1; then
      rm -f "${RUBY_BUILD_LOG}"
    else
      cat "${RUBY_BUILD_LOG}"
      rm -f "${RUBY_BUILD_LOG}"
      # The Gemfile accepts any 4.x, so the newest installed patch release of the
      # same minor version beats failing every step below.
      FALLBACK="$(rbenv versions --bare | grep "^${RUBY_VERSION%.*}\." | sort -V | tail -1 || true)"
      [ -n "${FALLBACK}" ] || exit 1
      echo "== Ruby ${RUBY_VERSION} could not be installed, using ${FALLBACK} =="
      repair_toolcache_layout "${FALLBACK}"
      export RBENV_VERSION="${FALLBACK}"
      if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
        echo "export RBENV_VERSION=\"${FALLBACK}\"" >> "${CLAUDE_ENV_FILE}"
      fi
    fi
  fi
fi
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
