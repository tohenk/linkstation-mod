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

extract_initrd_cpio() {
  local OUTDIR=$1
  local IMG=$2
  local INITRD_GZ=$3
  local INITRD=`basename $INITRD_GZ`
  INITRD="`dirname $INITRD_GZ`/${INITRD%.*}"
  dd if="$IMG" of="$INITRD_GZ" ibs=64 skip=1 1>/dev/null 2>/dev/null
  gunzip "$INITRD_GZ"
  clean_dir "$OUTDIR"
  cd "$OUTDIR" && cat "$INITRD" | cpio -id --quiet
}

create_initrd_cpio() {
  local SRCDIR=$1
  local INITRD=$2
  local INITRD_IMG=$3
  cd "$SRCDIR" && find . | cpio -oH newc --quiet > "$INITRD"
  gzip -f "$INITRD"
  mkimage -A ARM -O Linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 -n initrd -d "${INITRD}.gz" "$INITRD_IMG" >/dev/null
  rm -f "${INITRD}.gz"
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

