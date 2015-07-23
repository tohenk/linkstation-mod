#!/bin/bash

if [ ! -f "$1" ]; then
  echo "File not found $1.\n"
  exit 1
fi
if [ -z "$2" ]; then
  echo "Please specify output directory.\n"
  exit 1
fi

MYDIR=`dirname $0`
MYDIR=`pushd $MYDIR > /dev/null && pwd -P && popd > /dev/null`
ROOT=`pwd`
IMG=$1
OUTDIR=$2

. $MYDIR/ls-functions.sh

PASSWORD=`unpack_buffalo_image "$OUTDIR" "$IMG"`
if [ -n "$PASSWORD" ]; then
  echo "Image $IMG unpacked using password $PASSWORD."
fi
