#!/bin/sh

set -eu

: "${FAKE_CURL_LOG:?FAKE_CURL_LOG must be set}"
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f|-s|-S|-fsS) shift ;;
    --max-time) shift 2 ;;
    -H)
      [ "$#" -ge 2 ] || exit 64
      if [ "$2" = @- ]; then
        IFS= read -r authorization || true
      fi
      shift 2
      ;;
    http://*|https://*) url=$1; shift ;;
    *) printf '%s\n' "fake-curl: unsupported argument $1" >&2; exit 64 ;;
  esac
done

printf '%s\n' "$url" >>"$FAKE_CURL_LOG"
case "${FAKE_MODEL_DISCOVERY_MODE:-success}" in
  success)
    printf '%s\n' '{"object":"list","data":[{"id":"deepseek-v4-flash","object":"model"},{"id":"deepseek-v4-pro","object":"model"},{"id":"deepseek-v4-flash","object":"model"},{"id":"bad model","object":"model"}]}'
    ;;
  unsupported) exit 22 ;;
  malformed) printf '%s\n' '{"object":"list","data":[]}' ;;
  *) printf '%s\n' 'fake-curl: invalid discovery mode' >&2; exit 64 ;;
esac
