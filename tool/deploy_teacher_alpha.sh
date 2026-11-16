#!/bin/sh
# Builds the web version of the current branch (meant for `teacher`) without
# sync and deploys it to the web-only Worker "bbu-teacher-alpha"
# (worker/wrangler.teacher-alpha.jsonc):
#   https://bbu-teacher-alpha.brandart1.workers.dev
# Needs CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID (Workers edit), e.g.
#   set -a; . /root/better-betteruntis-keys/cloudflare.env; set +a
set -eu
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn \
  --dart-define=BBU_CHANNEL=alpha \
  --dart-define=BBU_NO_SYNC=true
rm -rf worker/public-teacher-alpha
mkdir -p worker/public-teacher-alpha
cp -R build/web/. worker/public-teacher-alpha/
cp worker/public/_headers worker/public-teacher-alpha/_headers
cd worker
npx wrangler deploy -c wrangler.teacher-alpha.jsonc
