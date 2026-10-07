#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Brings a remote container to the point where `mix format --check-formatted`,
# `mix compile --warnings-as-errors` and `mix test` run unattended: Erlang/OTP and
# Elixir from .tool-versions on PATH, Hex deps fetched and compiled, the esbuild
# binary installed and a device config in place.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Both come precompiled from builds.hex.pm (or the mirror in $HEX_BUILDS_URL, as for
# Hex itself); versions are pinned once, in .tool-versions, which erlef/setup-beam
# reads in GitHub Actions as well.
BUILDS_URL="${HEX_BUILDS_URL:-https://builds.hex.pm}"
ERLANG_VERSION="$(awk '$1 == "erlang" { print $2 }' .tool-versions)"
ELIXIR_VERSION="$(awk '$1 == "elixir" { print $2 }' .tool-versions)"
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

# config/ziwoas.yml is gitignored and holds device credentials. The test config
# describes the same shape with fixture values and talks to no real device.
if [ ! -f config/ziwoas.yml ]; then
  echo "== Seeding config/ziwoas.yml from test/fixtures/ziwoas.test.yml =="
  cp test/fixtures/ziwoas.test.yml config/ziwoas.yml
fi

echo "== Fetching and compiling deps =="
mix deps.get > /dev/null
MIX_ENV=test mix deps.compile > /dev/null

# The esbuild binary comes from the npm registry; without it only `mix assets.*`
# fails, so a blocked download warns instead of stopping the session setup.
if grep -q '"assets.setup"' mix.exs; then
  echo "== Installing esbuild =="
  mix assets.setup > /dev/null || echo "WARNING: esbuild could not be installed; mix assets.* is unavailable this session." >&2
fi

echo "== Setup complete =="
