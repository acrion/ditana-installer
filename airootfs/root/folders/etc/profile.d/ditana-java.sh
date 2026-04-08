# Set JAVA_HOME and JAVA_COMPILER via archlinux-java

if command -v archlinux-java > /dev/null 2>&1; then
    export JAVA_HOME="/usr/lib/jvm/$(archlinux-java get)"
fi

if [[ -x "$JAVA_HOME/bin/javac" ]]; then
    export JAVA_COMPILER="$JAVA_HOME/bin/javac"
fi
