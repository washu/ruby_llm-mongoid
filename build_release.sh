#!/bin/bash
set -euo pipefail

# Maintainer release helper.
#
# Usage:
#   SKIP_PUSH=1 ./build_release.sh       # build and verify only
#   ./build_release.sh                   # build, then let `gem push` prompt for MFA
#   GEM_HOST_OTP=123456 ./build_release.sh  # build and publish with explicit OTP

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

VERSION="$(ruby -r ./lib/ruby_llm/mongoid/version.rb -e 'puts RubyLLM::Mongoid::VERSION')"
GEM_FILE="ruby_llm-mongoid-${VERSION}.gem"

echo "Building gem version ${VERSION}..."
rm -f "$GEM_FILE"
gem build ruby_llm-mongoid.gemspec

if [[ ! -f "$GEM_FILE" ]]; then
  echo "Expected gem file not found: $GEM_FILE" >&2
  exit 1
fi

if [[ "${SKIP_PUSH:-0}" == "1" ]]; then
  echo "SKIP_PUSH=1 set; build verified, skipping publish."
  exit 0
fi

echo "Pushing $GEM_FILE to RubyGems..."
if [[ -n "${GEM_HOST_OTP:-}" ]]; then
  gem push "$GEM_FILE" --otp "$GEM_HOST_OTP"
else
  gem push "$GEM_FILE"
fi

echo "Done!"
