#!/bin/bash

kernel_latest_ver() {
  local VER=$1
  for DELIM in . -; do
    local TAGS=`git tag -l "v${VER}${DELIM}*"`
    if [ -n "$TAGS" ]; then
      break
    fi
  done
  # check if version exist
  if [ -n "$TAGS" ]; then
    local LVL=0
    for TAG in $TAGS; do
      IFS=. read -a VERS <<< "$TAG"
      # RC kernel
      if [ ${#VERS[@]} -eq 2 ]; then
        local KLVL=`echo "${VERS[1]}" | sed -e 's/\-rc[0-9]*//g'`
        if [ $KLVL -ge $LVL ]; then
          LVL=$KLVL
          local KVER="${VERS[0]}.${VERS[1]}"
        fi
      fi
      # release kernel
      if [ ${#VERS[@]} -gt 2 ]; then
        local KLVL=${VERS[2]}
        if [ $KLVL -ge $LVL ]; then
          LVL=$KLVL
          local KVER="${VERS[0]}.${VERS[1]}.${VERS[2]}"
        fi
      fi
    done
    echo $KVER
  fi
}
