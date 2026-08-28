#!/usr/bin/env bash
# Sync the Kafka reference sources used by the "exactly once" posts.
#
# Blobless + sparse clones of the upstream repos, pinned to a tag. Everything
# this script creates is gitignored: it is third-party source and fully
# reproducible by re-running the script. Only this file and the *-index.md
# steering notes are committed.
#
#   ./reference/kafka/sync.sh
#
set -euo pipefail

cd "$(dirname "$0")"

KAFKA_TAG="4.3.1"        # matches https://kafka.apache.org/43/ — the docs the posts cite
SPRING_KAFKA_TAG="v4.1.1"

# clone <dir> <repo> <tag> <sparse path>...
clone() {
  local dir=$1 repo=$2 tag=$3
  shift 3

  if [ -d "$dir/.git" ]; then
    local have
    have=$(git -C "$dir" describe --tags --exact-match 2>/dev/null || echo "")
    if [ "$have" = "$tag" ]; then
      echo "== $dir already at $tag"
      return
    fi
    echo "== $dir is at '${have:-unknown}', want $tag — re-cloning"
    rm -rf "$dir"
  fi

  echo "== cloning $repo @ $tag -> $dir"
  git clone --filter=blob:none --no-checkout --depth 1 --branch "$tag" "$repo" "$dir"
  git -C "$dir" sparse-checkout set --no-cone "$@"
  git -C "$dir" checkout
}

# The producer/consumer clients, the broker-side idempotence bookkeeping, the
# transaction coordinator, and docs/ — which holds the HTML source of
# design.html and configuration.html, i.e. the config doc strings and the
# "Message Delivery Semantics" text the posts quote.
clone apache-kafka https://github.com/apache/kafka.git "$KAFKA_TAG" \
  'clients/src/main/java/org/apache/kafka/clients/producer/' \
  'clients/src/main/java/org/apache/kafka/clients/consumer/' \
  'clients/src/main/java/org/apache/kafka/common/record/' \
  'storage/src/main/java/org/apache/kafka/storage/internals/log/' \
  'transaction-coordinator/src/main/java/' \
  'docs/'

clone spring-kafka https://github.com/spring-projects/spring-kafka.git "$SPRING_KAFKA_TAG" \
  'spring-kafka/src/main/java/org/springframework/kafka/' \
  'spring-kafka-docs/src/main/antora/modules/ROOT/pages/'

echo
echo "Done."
echo "  apache-kafka  $KAFKA_TAG"
echo "  spring-kafka  $SPRING_KAFKA_TAG"
