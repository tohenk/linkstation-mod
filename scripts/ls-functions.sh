#!/bin/sh

show_msg() {
  echo "> $1..."
}

show_info() {
  echo "  $1"
}

clean_dir() {
  if [ -d "$1" ]; then
    rm -rf "$1"
  fi
  mkdir -p "$1"
}

unpack_firmware() {
  local OUTDIR=$1
  local FIRMWARE=$2
  local IMGNAME=$3
  unzip -o "$FIRMWARE" -d "$OUTDIR" >/dev/null
  local IMG=`find $OUTDIR -name $IMGNAME 2>/dev/null`
  if [ "$?" -eq 0 ] && [ -n "$IMG" ]; then
    echo $IMG
  fi
}

unpack_buffalo_image() {
  local OUTDIR=$1
  local IMG=$2
  local PASSWORD=
  local PASSWORD_LIST="1NIf_2yUOlRDpYZUVNqboRpMBoZwT4PzoUvOPUp6l aAhvlM1Yp7_2VSm6BhgkmTOrCN1JyE0C5Q6cB3oBB YvSInIQopeipx66t_DCdfEvfP47qeVPhNhAuSYmA4 IeY8omJwGlGkIbJm2FH_MV4fLsXE8ieu0gNYwE6Ty"
  for PASSWORD in $PASSWORD_LIST; do
    unzip -o -P $PASSWORD "$IMG" -d "$OUTDIR" 1>/dev/null 2>/dev/null
    if [ "$?" -eq 0 ]; then
      echo $PASSWORD
      break
    fi
  done
}

extract_rootfs() {
  local OUTDIR=$1
  local IMG=$2
  clean_dir "$OUTDIR"
  tar --numeric-owner -p -zxf "$IMG" -C "$OUTDIR" 1>/dev/null 2>/dev/null
}

package_rootfs() {
  local SRCDIR=$1
  local IMG=$2
  cd "$SRCDIR" && tar --numeric-owner -p -czf "$IMG" *
}

extract_initrd() {
  local COMPRESSOR=$1
  local OUTDIR=$2
  local IMG=$3
  local INITRD_FILE=$4
  local MYCMD=

  case $COMPRESSOR in
    gzip)
      MYCMD="gunzip"
      ;;
    bzip2)
      MYCMD="bunzip2"
      ;;
    lzma)
      MYCMD="xz -F lzma --decompress"
      ;;
    lzo)
      MYCMD="lzop --decompress"
      ;;
    *)
      show_info "Unsupported de-compressor $COMPRESSOR."
      return
      ;;
  esac

  local INITRD=`basename $INITRD_FILE`
  INITRD="`dirname $INITRD_FILE`/${INITRD%.*}"
  dd if="$IMG" of="$INITRD_FILE" ibs=64 skip=1 1>/dev/null 2>/dev/null
  $MYCMD "$INITRD_FILE"
  clean_dir "$OUTDIR"
  cd "$OUTDIR" && cat "$INITRD" | cpio -id --quiet
}

create_initrd() {
  local COMPRESSOR=$1
  local SRCDIR=$2
  local INITRD=$3
  local INITRD_IMG=$4
  local MYCMD=
  local MYOUT=

  case $COMPRESSOR in
    gzip)
      MYCMD="gzip -f"
      MYOUT=${INITRD}.gz
      ;;
    bzip2)
      MYCMD="bzip2 -z"
      MYOUT=${INITRD}.bz2
      ;;
    lzma)
      MYCMD="xz -F lzma -z"
      MYOUT=${INITRD}.lzma
      ;;
    lzo)
      MYCMD="lzop"
      MYOUT=${INITRD}.lzo
      ;;
    *)
      show_info "Unsupported compressor $COMPRESSOR."
      return
      ;;
  esac
  cd "$SRCDIR" && find . | cpio -oH newc --quiet > "$INITRD"
  $MYCMD "$INITRD"
  mkimage -A ARM -O Linux -T ramdisk -C $COMPRESSOR -a 0x00000000 -e 0x00000000 -n initrd -d "$MYOUT" "$INITRD_IMG" >/dev/null
  rm -f "$MYOUT"
}

pack_firmware() {
  local SRCDIR=$1
  local IMG=$2
  local IMGNAME=$3
  local PASSWORD=$4
  cd "$SRCDIR" && zip -m -P $PASSWORD "$IMG" "$IMGNAME" >/dev/null
}

emergency_script() {
  cat <<EOF
#!/bin/sh

# run emergency script
[ -f /mnt/disk1/share/emergency.sh ] && {
  /bin/sh /mnt/disk1/share/emergency.sh
  exit 0
}
[ -f /mnt/array1/share/emergency.sh ] && {
  /bin/sh /mnt/array1/share/emergency.sh
  exit 0
}
EOF
}

remove_root_password() {
  local SRC=$1
  local BACKUP=$2
  local PATTERN='s/root:[^:]*?:/root::/'
  if [ -z "$BACKUP" ]; then
    perl -pe $PATTERN -i "$SRC"
  else
    mv "$SRC" "$BACKUP"
    cat "$BACKUP" | perl -pe $PATTERN > "$SRC"
  fi
}

linuxrc_raid() {
  local ROOT=$1
  cat <<EOF
#!/bin/sh
 
# Mount the /proc and /sys filesystems.
mount -t proc none /proc
mount -t sysfs none /sys
 
echo 'DEVICE /dev/sd??*' > /etc/mdadm/mdadm.conf
mdadm -Eb /dev/sd??* >> /etc/mdadm/mdadm.conf
mdadm -As --force
 
echo "$ROOT" > /proc/sys/kernel/real-root-dev
 
# Clean up.
umount /proc
umount /sys

exit 0
EOF
}

