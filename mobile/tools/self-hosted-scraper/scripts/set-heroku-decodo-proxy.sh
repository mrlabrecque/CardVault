#!/usr/bin/env bash
# Push residential proxy settings to a Heroku app running the self-hosted scraper.
# Usage:
#   cd mobile/tools/self-hosted-scraper
#   export HEROKU_APP=your-scraper-app
#   export DECODO_PROXY_SERVER=http://gate.example.com:10001
#   export DECODO_PROXY_USERNAME=...
#   export DECODO_PROXY_PASSWORD=...
#   npm run heroku:set-proxy
#
# Or a single URL:
#   export DECODO_PROXY_URL=http://user:pass@host:port
#   npm run heroku:set-proxy
#
# Optional: put exports in .env (gitignored) and run: set -a && source .env && set +a && npm run heroku:set-proxy

set -euo pipefail

APP="${HEROKU_APP:-${1:-}}"
if [[ -z "$APP" ]]; then
  echo "Set HEROKU_APP to your Heroku app name, or pass it as the first argument."
  echo "Example: HEROKU_APP=cardvault-scraper npm run heroku:set-proxy"
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CONFIG_ARGS=()

if [[ -n "${DECODO_PROXY_URL:-}" ]]; then
  CONFIG_ARGS+=(DECODO_PROXY_URL="$DECODO_PROXY_URL")
elif [[ -n "${SELF_HOSTED_PROXY_URL:-}" ]]; then
  CONFIG_ARGS+=(SELF_HOSTED_PROXY_URL="$SELF_HOSTED_PROXY_URL")
fi

if [[ -n "${DECODO_PROXY_SERVER:-}" ]]; then
  CONFIG_ARGS+=(DECODO_PROXY_SERVER="$DECODO_PROXY_SERVER")
  [[ -n "${DECODO_PROXY_USERNAME:-}" ]] && CONFIG_ARGS+=(DECODO_PROXY_USERNAME="$DECODO_PROXY_USERNAME")
  [[ -n "${DECODO_PROXY_PASSWORD:-}" ]] && CONFIG_ARGS+=(DECODO_PROXY_PASSWORD="$DECODO_PROXY_PASSWORD")
elif [[ -n "${SELF_HOSTED_PROXY_SERVER:-}" ]]; then
  CONFIG_ARGS+=(SELF_HOSTED_PROXY_SERVER="$SELF_HOSTED_PROXY_SERVER")
  [[ -n "${SELF_HOSTED_PROXY_USERNAME:-}" ]] && CONFIG_ARGS+=(SELF_HOSTED_PROXY_USERNAME="$SELF_HOSTED_PROXY_USERNAME")
  [[ -n "${SELF_HOSTED_PROXY_PASSWORD:-}" ]] && CONFIG_ARGS+=(SELF_HOSTED_PROXY_PASSWORD="$SELF_HOSTED_PROXY_PASSWORD")
fi

if [[ ${#CONFIG_ARGS[@]} -eq 0 ]]; then
  echo "No proxy variables found. Set one of:"
  echo "  DECODO_PROXY_URL, or DECODO_PROXY_SERVER (+ USERNAME/PASSWORD), or"
  echo "  SELF_HOSTED_PROXY_URL, or SELF_HOSTED_PROXY_SERVER (+ USERNAME/PASSWORD)"
  echo "(in the environment or in .env in this directory)"
  exit 1
fi

echo "heroku config:set ... -a $APP"
heroku config:set "${CONFIG_ARGS[@]}" -a "$APP"

echo ""
echo "Done. Check with: curl -s https://\${APP}.herokuapp.com/health | jq .proxyConfigured"
echo "Optional hard-fail without proxy: heroku config:set SELF_HOSTED_REQUIRE_PROXY=true -a $APP"
