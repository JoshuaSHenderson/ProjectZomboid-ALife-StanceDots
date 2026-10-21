#!/bin/sh
# Builds the Viewpoint bridge jar. No JDK needed: runs the Eclipse compiler
# (ecj, Maven Central) on the Java the game ships with.
#   PZ=/path/to/ProjectZomboid ECJ=/path/to/ecj.jar sh tools/build_viewpoint_jar.sh
set -e
PZ=${PZ:-"/d/SteamLibrary/steamapps/common/ProjectZomboid"}
ECJ=${ECJ:?"set ECJ to an ecj jar, e.g. https://repo1.maven.org/maven2/org/eclipse/jdt/ecj/3.46.100/ecj-3.46.100.jar"}
MOD=ALifeStanceDots/Contents/mods/ALifeStanceDotsViewpoint/42
OUT=$(mktemp -d)
# Windows java wants a ;-separated Windows classpath
CP="$PZ/projectzomboid.jar:$PZ/ZombieBuddy.jar"
command -v cygpath >/dev/null && CP=$(cygpath -wp "$CP")

"$PZ/jre64/bin/java" -jar "$ECJ" -source 17 -target 17 -nowarn \
    -cp "$CP" -d "$OUT" "$MOD/src/alifestancedots/viewpoint/Bridge.java"
mkdir -p "$MOD/media/java/client"
rm -f "$MOD/media/java/client/ALifeStanceDotsViewpoint.jar"
# the game's JRE has no jar tool; a jar is a zip
(cd "$OUT" && python -c "import zipfile,os;z=zipfile.ZipFile('jar.jar','w');[z.write(os.path.join(d,f)) for d,_,fs in os.walk('alifestancedots') for f in fs];z.close()")
mv "$OUT/jar.jar" "$MOD/media/java/client/ALifeStanceDotsViewpoint.jar"
rm -rf "$OUT"
echo "built $MOD/media/java/client/ALifeStanceDotsViewpoint.jar"
