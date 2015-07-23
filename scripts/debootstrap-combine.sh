#!/bin/bash

# check for parameters
if [ $# -ne 3 ]; then
  echo "Usage:"
  echo "  `basename $0` ROOTFS INITRDFS LS_FIRMWARE_DIR"
  echo ""
  echo "Where:"
  echo "  ROOTFS            The tar archive of root file system"
  echo "  INITRDFS          The tar archive of initrd file system"
  echo "  LS_FIRMWARE_DIR   The directory for LS firmware (must contain hddrootfs.img)"
  echo ""
  exit 1
fi
if [ ! -f "$1" ]; then
  echo "Root file system not found: $1.\n"
  exit 1
fi
if [ ! -f "$2" ]; then
  echo "Initrd file system not found: $1.\n"
  exit 1
fi
if [ ! -d "$3" ] || [ ! -f "$3/hddrootfs.img" ]; then
  echo "Not a LS firmware dir: $3.\n"
  exit 1
fi

MYDIR=`dirname $0`
MYDIR=`pushd $MYDIR > /dev/null && pwd -P && popd > /dev/null`
ROOT=`pwd`
OUTDIR=$ROOT/out
DATADIR=$ROOT/data
TMP=$ROOT/tmp
WORK_DIR=$TMP/WORK
HDDROOT_DIR=$TMP/HDDROOT
INITRD_DIR=$TMP/INITRD
ROOTFS_IMG=$1
INITRD_IMG="$2"
HDDROOT_IMG="$3/hddrootfs.img"

. $MYDIR/ls-functions.sh
. $MYDIR/debootstrap-combine.cfg

HOSTNAME=${HOSTNAME:=LS421DE}
NETWORK_INTERFACE=${NETWORK_INTERFACE:=eth0}
NETWORK_PROTO=${NETWORK_PROTO:=static}
NETWORK_IP=${NETWORK_IP:=192.168.11.150}
NETWORK_NETMASK=${NETWORK_NETMASK:=255.255.255.0}
NETWORK_GATEWAY=${NETWORK_GATEWAY:=192.168.11.1}
NETWORK_DNS=${NETWORK_DNS:=192.168.11.1}
NETWORK_DOMAIN=${NETWORK_DOMAIN:=}

INITRD_TEMP_ROOT=${INITRD_TEMP_ROOT:=}
INITRD_ROOT=${INITRD_ROOT:=}
INITRD_FORMAT=${INITRD_FORMAT:=gzip}

do_prep_dirs() {
  show_msg "Preparing directories"
  local DIRS="$TMP"
  for D in $DIRS; do
    clean_dir "$D"
  done
  mkdir -p "$OUTDIR"
}

do_unpack_rootfs() {
  show_msg "Unpacking ROOTFS"
  extract_rootfs "$WORK_DIR" "$ROOTFS_IMG"
}

do_unpack_initrdfs() {
  show_msg "Unpacking INITRD"
  extract_rootfs "$INITRD_DIR" "$INITRD_IMG"
}

do_unpack_hddrootfs() {
  show_msg "Unpacking LinkStation ROOTFS"
  unpack_buffalo_image "$TMP" "$HDDROOT_IMG" >/dev/null
  extract_rootfs "$HDDROOT_DIR" "$TMP/hddrootfs.buffalo.updated"
}

do_create_rootfs() {
  show_msg "Creating ROOTFS for LinkStation"
  show_info "Cleaning /proc."
  clean_dir "$WORK_DIR/proc"
  show_info "Updating fstab."
  local HAS_FSTAB=false
  if [ -n "$INITRD_TEMP_ROOT" -a "x$INITRD_TEMP_ROOT" != "x$INITRD_ROOT" ]; then
    if [ -f "$DATADIR/fstab.tmp" ]; then
      cp "$DATADIR/fstab.tmp" "$WORK_DIR/etc/fstab"
      if [ -f "$DATADIR/fstab" ]; then
        cp "$DATADIR/fstab" "$WORK_DIR/etc/fstab~"
      fi
      HAS_FSTAB=true
    fi
  fi
  if [ "$HAS_FSTAB" = "false" -a -f "$DATADIR/fstab" ]; then
    cp "$DATADIR/fstab" "$WORK_DIR/etc/fstab"
  fi
  show_info "Setting hostname."
  echo $HOSTNAME >"$WORK_DIR/etc/hostname"
  sed -i -e "s/127\.0\.0\.1\tlocalhost/127\.0\.0\.1\tlocalhost $HOSTNAME/" "$WORK_DIR/etc/hosts"
  show_info "Applying network config."
  if [ -f "$DATADIR/interfaces" ]; then
    cp "$DATADIR/interfaces" "$WORK_DIR/etc/network/interfaces"
  else
    (
    cat <<EOF

auto $NETWORK_INTERFACE
iface $NETWORK_INTERFACE inet $NETWORK_PROTO
EOF
    ) >>"$WORK_DIR/etc/network/interfaces"
    if [ "x$NETWORK_PROTO" = "xstatic" ]; then
      (
      cat <<EOF
  address $NETWORK_IP
  netmask $NETWORK_NETMASK
  gateway $NETWORK_GATEWAY
EOF
      ) >>"$WORK_DIR/etc/network/interfaces"
      rm -f "$WORK_DIR/etc/resolv.conf"
      touch "$WORK_DIR/etc/resolv.conf"
      if [ -n "$NETWORK_DNS" ]; then
        echo "nameserver $NETWORK_DNS" >>"$WORK_DIR/etc/resolv.conf"
      fi
      if [ -n "$NETWORK_DOMAIN" ]; then
        echo "search $NETWORK_DOMAIN" >>"$WORK_DIR/etc/resolv.conf"
      fi
    fi
  fi
  show_info "Creating mount point."
  cd "$WORK_DIR" && mkdir -p media/disk1 media/disk2
  show_info "Copying kernel modules."
  cd "$HDDROOT_DIR" && tar -cf - lib/modules/ | (cd "$WORK_DIR"; tar -xf -)
  show_info "Package ROOTFS."
  package_rootfs "$WORK_DIR" "$OUTDIR/hddrootfs.buffalo.updated"
}

do_create_temp_initrd() {
  show_msg "Creating temporary INITRD"
  if [ -f "$DATADIR/linuxrc.tmp" ]; then
    show_info "Using linuxrc.tmp provided in the data dir."
    cp "$DATADIR/linuxrc.tmp" "$INITRD_DIR/linuxrc"
  else
    show_info "linuxrc root set to $INITRD_TEMP_ROOT."
    linuxrc_raid $INITRD_TEMP_ROOT >"$INITRD_DIR/linuxrc" 
  fi
  chmod +x "$INITRD_DIR/linuxrc"
  create_initrd $INITRD_FORMAT "$INITRD_DIR" "$OUTDIR/initrd" "$OUTDIR/initrd.buffalo.temporary"
}

do_create_initrd() {
  show_msg "Creating INITRD"
  if [ -f "$DATADIR/linuxrc" ]; then
    show_info "Using linuxrc provided in the data dir."
    cp "$DATADIR/linuxrc" "$INITRD_DIR/linuxrc"
  elif [ -n "$INITRD_ROOT" ]; then
    show_info "linuxrc root set to $INITRD_ROOT."
    linuxrc_raid $INITRD_ROOT >"$INITRD_DIR/linuxrc" 
  fi
  chmod +x "$INITRD_DIR/linuxrc"
  create_initrd $INITRD_FORMAT "$INITRD_DIR" "$OUTDIR/initrd" "$OUTDIR/initrd.buffalo"
}

main() {
  echo "Preparing Debian for LinkStation."

  do_prep_dirs
  do_unpack_rootfs
  do_unpack_initrdfs
  do_unpack_hddrootfs
  do_create_rootfs
  [ -n "$INITRD_TEMP_ROOT" -a "x$INITRD_TEMP_ROOT" != "x$INITRD_ROOT" ] && {
    do_create_temp_initrd
  }
  do_create_initrd

  echo "Done."
  echo
}

main
exit 0
