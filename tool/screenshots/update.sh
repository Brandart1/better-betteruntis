#!/bin/sh
# Regenerates docs/screenshots/*.png from the demo data.
cd "$(dirname "$0")/../.." && flutter test tool/screenshots/screenshots_test.dart --update-goldens "$@"
