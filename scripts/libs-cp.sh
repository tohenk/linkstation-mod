#!/bin/sh

TARGET=$1
BASE_TARGET=`dirname $TARGET`

find "$TARGET" -type f -exec sh -c "
cp_lib() {
  local LIBS=\"\$(ldd \"\$1\" | grep -v \"^$BASE_TARGET\" | sed -e 's/.*=> *//'  -e 's/ *(.*//' | sort -u)\"
  for LIB in "\$LIBS"; do
    LIB=\${LIB%% }
    LIB=\${LIB## }
    local LSRC=\"\$LIB\"
    local LDEST=\"$BASE_TARGET\$LIB\"
    if [ ! -f \"\$LDEST\" -a -f \"\$LSRC\" ]; then
      mkdir -p \`dirname \$LDEST\`
      cp -aLv \"\$LSRC\" \"\$LDEST\"
    fi
  done
}
cp_libs() {
  for FILE in \$@; do
    cp_lib \"\$FILE\"
  done
}
cp_libs \"\$@\"" sh {} +;
