#!/usr/bin/env bash
# Build Vessel_Permeability-1.1.0.jar without Maven.
# Usage:  ./build.sh /path/to/Fiji.app/jars/ij-1.54*.jar
#   (any ImageJ 1.x ij.jar works; Fiji keeps it in Fiji.app/jars/)
set -euo pipefail
IJ_JAR="${1:?Pass the path to ij.jar, e.g. Fiji.app/jars/ij-1.54f.jar}"
cd "$(dirname "$0")"
rm -rf build && mkdir -p build/classes
javac -encoding UTF-8 --release 8 -Xlint:-options -cp "$IJ_JAR" -d build/classes \
    src/main/java/vesselpermeability/*.java
cp src/main/resources/plugins.config build/classes/
(cd build/classes && jar cf ../Vessel_Permeability-1.1.0.jar .)
echo "Built build/Vessel_Permeability-1.1.0.jar - copy it into Fiji.app/plugins/"
