#!/bin/bash

choices() {
  local NAME=$1[@]
  local ITEMS=("${!NAME}")
  local TITLE=$2
  local CHOICE=-1
  local INPUT
  if [ "x$3" = "x" ]; then
    local FMT="%d. %s"
  else
    local FMT=$3
  fi
  local I=0
  local LEN=${#ITEMS[*]}
  if [ $LEN -ge 1 ]; then
    # populate choices
    echo "${TITLE}:"
    for A in "${ITEMS[@]}"; do
      I=$((I+1))
      echo $(printf "$FMT" $I "$A")
    done
    if [ $LEN -gt 1 ]; then
      local MSG="Type choice [1-${LEN}]?"
    else
      local MSG="Type choice [${LEN}]?"
    fi
    # wait for input
    while true; do
      echo -n "$MSG " && read INPUT
      # ignore if just empty
      if [ -z "$INPUT" ]; then
        CHOICE=0
        break
      fi
      if [ $INPUT -ge 1 -a $INPUT -le $LEN ]; then
        CHOICE=$INPUT
        break
      fi
    done
  fi
  return $CHOICE
}

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

get_toolchain() {
  local DIR=$1
  local TCS=
  [ -d $DIR ] && {
    for TC in `cd $DIR && ls`; do
      [ -d "$DIR/$TC/bin" ] && {
        local TC_BINS=`cd $DIR/$TC/bin && ls arm-linux-gnueabihf-* 2>/dev/null`
        if [ -n "$TC_BINS" ]; then
          if [ -z "$TCS" ]; then
            TCS=$TC
          else
            TCS="$TCS $TC"
          fi
        fi
      }
    done
  }
  echo $TCS
}

check_toolchain() {
  local STATE=2
  local TCS=$(get_toolchain $1)
  if [ -n "$TCS" ]; then
    local STATE=1
    for TC in $TCS; do
      [ "x$2" = "x$TC" ] && {
        STATE=0
        echo "$1/$TC/bin/arm-linux-gnueabihf-"
        break;
      }
    done
  fi
  return $STATE
}

toolchain_not_found() {
  local DIR=$1
  echo "No toolchain found!"
  echo ""
  echo "Toolchain can be downloaded from:"
  echo "  http://releases.linaro.org/components/toolchain/binaries/"
  echo "After the download is complete, place the extracted content to:"
  echo "  $DIR"
  echo ""
}
