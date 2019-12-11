#!/bin/bash
set -e

COMPILER_MAJOR_VERSION=`echo ${COMPILER_VERSION} | awk -F . '{print $1}'`
TEST_OPTIONS="-c release"

if [[ "$1" == "--tsan" && "$TRAVIS_OS_NAME" != "linux" ]]
then
  # the linux version of the thread sanitizer trips on libdispatch,
  # therefore don't enable it on linux.
  echo "enabling thread sanitizer"
  TEST_OPTIONS="${TEST_OPTIONS} --sanitize=thread"
  export TSAN_OPTIONS="suppressions=Tests/tsan-suppression"
fi

swift --version
swift test ${TEST_OPTIONS}

if [[ "${COMPILER_MAJOR_VERSION}" = "5" ]]
then
  VERSIONS="4.2 4"
fi

for LANGUAGE_VERSION in $VERSIONS
do
  echo "" # add a small visual separation
  echo "Testing in compatibility mode for Swift ${LANGUAGE_VERSION}"
  swift package reset
  rm -f Package.resolved
  swift test ${TEST_OPTIONS} -Xswiftc -swift-version -Xswiftc ${LANGUAGE_VERSION}
done
