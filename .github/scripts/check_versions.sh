#!/usr/bin/env bash
# Check that every place that states the software version agrees.
# Usage: .github/scripts/check_versions.sh [release-tag]
#   With a tag (e.g. v1.1.0), also check that it matches the version.
set -euo pipefail
cd "$(dirname "$0")/../.."

matlab=$(sed -n 's/^v = "\(.*\)";.*/\1/p' permeabilityVersion.m)
contents=$(sed -n 's/^% Version \([^ ]*\) .*/\1/p' Contents.m)
cff=$(sed -n 's/^version: *\(.*\)$/\1/p' CITATION.cff)
pom=$(sed -n 's/.*<version>\(.*\)<\/version>.*/\1/p' imagej/pom.xml | head -1)
java=$(sed -n 's/.*String VERSION = "\(.*\)";.*/\1/p' \
    imagej/src/main/java/vesselpermeability/Vessel_Permeability.java)
buildsh=$(sed -n 's/.*Vessel_Permeability-\([0-9][0-9.]*\)\.jar.*/\1/p' imagej/build.sh | sort -u)
buildbat=$(sed -n 's/.*Vessel_Permeability-\([0-9][0-9.]*\)\.jar.*/\1/p' imagej/build.bat | sort -u)

status=0
check() {
    if [ "$2" != "$matlab" ]; then
        echo "MISMATCH: $1 says '$2', permeabilityVersion.m says '$matlab'"
        status=1
    fi
}
check "Contents.m" "$contents"
check "CITATION.cff" "$cff"
check "imagej/pom.xml" "$pom"
check "Vessel_Permeability.java VERSION" "$java"
check "imagej/build.sh" "$buildsh"
check "imagej/build.bat" "$buildbat"
if [ $# -ge 1 ]; then
    check "release tag" "${1#v}"
fi
[ $status -eq 0 ] && echo "All versions are $matlab"
exit $status
