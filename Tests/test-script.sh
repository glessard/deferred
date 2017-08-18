#!/bin/bash
set -e

if [[ -n "${SWIFT_VERSION}" ]]
then
  swift package tools-version --set "${SWIFT_VERSION}"
fi

swift test
