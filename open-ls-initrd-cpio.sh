#!/bin/sh

# Original script from http://buffalo.nas-central.org/wiki/Open_Stock_Firmware_LS-XHL
# Modified by Toha <tohenk@yahoo.com>

# check for parameters
if [ $# -ne 1 ]; then
  echo "You have to specify the filename of the firmware zip-file!\n"
  exit 1
fi
if [ ! -f "$1" ]; then
  echo "File not found $1.\n"
  exit 1
fi

ROOT=`pwd`
OUTDIR=$ROOT/out
TMP=$ROOT/tmp
ORIGINAL=$TMP/ORIG
INITRD=$TMP/INITRD
INITRD_IMG_NAME=initrd.img
INITRD_FILE_NAME=initrd.buffalo
FIRMWARE=$1

. $ROOT/ls-functions.sh

do_prep_dirs() {
  show_msg "Preparing directories"
  local DIRS="$ORIGINAL $INITRD"
  for D in $DIRS; do
    clean_dir "$D"
  done
  mkdir -p "$OUTDIR"
}

do_unpack_firmware() {
  show_msg "Unpacking firmware"
  INITRD_IMG=`unpack_firmware "$TMP" "$FIRMWARE" "$ROOTFS_IMG_NAME"`
  if [ -n "$INITRD_IMG" ]; then
    show_info "Found INITRD image: $INITRD_IMG."
  else
    show_info "No INITRD image found! May be it not a valid LinkStation firmware.\n"
  fi
}

do_unpack_initrd() {
  show_msg "Unpacking INITRD image"
  PASSWORD=`unpack_buffalo_image "$ORIGINAL" "$INITRD_IMG"`
  if [ -n "$PASSWORD" ]; then
    show_info "Using password $PASSWORD."
  else
    show_info "Can't unpack INITRD image, no password matched.\n"
  fi
}

do_extract_initrd_cpio() {
  show_msg "Extracting INITRD using cpio"
  extract_initrd_cpio "$INITRD" "$ORIGINAL/$INITRD_FILE_NAME" "$ORIGINAL/initrd.gz"
}

do_enable_sftp() {
  show_msg "Enable SFTP in nas_features"
  if [ -d "$INITRD/root/.nas_features" ]; then
    find "$INITRD/root/.nas_features" -type f -exec sed -i -e "s/SUPPORT_SFTP=0/SUPPORT_SFTP=1/" {} \;
  else
    show_info "Skipping SFTP, nas_features not found."
  fi
}

do_patch_features() {
  show_msg "Patching nas_features"
  if [ -d "$INITRD/root/.nas_features" ] && [ -f "$ROOT/data/nas_features" ]; then
    show_info "Applying patch from $ROOT/data/nas_features."
    SEP=';'
    find "$INITRD/root/.nas_features" -type f -exec sh -c "
set_feature() {
  while read FEATURE; do
    case \$FEATURE in
      \#*)
        ;;
      *)
        FEATURE_OLD=\`echo \"\$FEATURE\" | awk -F'$SEP' '{print \$1}'\`
        FEATURE_NEW=\`echo \"\$FEATURE\" | awk -F'$SEP' '{print \$2}'\`
        sed -i -e \"s/\$FEATURE_OLD/\$FEATURE_NEW/\" \$1
        ;;
    esac
  done < \"$ROOT/data/nas_features\"
}
set_features() {
  for FILE in \$@; do
    set_feature \"\$FILE\"
  done
}
set_features \"\$@\"" sh {} +;
  fi
}

do_remove_root_password() {
  show_msg "Removing root password"
  remove_root_password "$INITRD/etc/shadow" "$INITRD/etc/shadow~"
  chmod 0644 "$INITRD/etc/shadow"
}

do_create_emergency_script() {
  show_msg "Creating emergency script service"
  EMERG_SCRIPT="$INITRD/etc/init.d/emergency.sh"
  emergency_script >$EMERG_SCRIPT
  chmod 0755 $EMERG_SCRIPT
}

do_run_emergency_script_in_rcS() {
  show_msg "Adding emergency script to run in /etc/init.d/rcS"
  RCS="$INITRD/etc/init.d/rcS"
  if [ -f "$RCS" ] && [ -n `cat $RCS | grep 'exec-sh()'` ]; then
    show_info "Emergency script added in rcS."
    echo "exec-sh emergency.sh" >> $RCS
  fi
}

do_package_initrd() {
  show_msg "Create and package INITRD"
  create_initrd_cpio "$INITRD" "$OUTDIR/initrd" "$OUTDIR/$INITRD_FILE_NAME"
  pack_firmware "$OUTDIR" "$INITRD_IMG_NAME" "$INITRD_FILE_NAME" "$PASSWORD"
  if [ -f "$OUTDIR/$INITRD_IMG_NAME" ]; then
    show_info "Opened INITRD image saved in $OUTDIR/$INITRD_IMG_NAME."
  fi
}

main() {
  echo "Opening stock firmware INITRD of $FIRMWARE."

  FNAME=`basename $FIRMWARE`
  FEXT="${FNAME##*.}"

  do_prep_dirs
  if [ "$FEXT" = "img" ]; then
    INITRD_IMG=$FIRMWARE
    INITRD_IMG_NAME=$FNAME
  else
    do_unpack_firmware
  fi
  if [ ! -f "$INITRD_IMG" ]; then
    exit 1;
  fi
  do_unpack_initrd
  if [ -z "$PASSWORD" ]; then
    exit 1;
  fi
  do_extract_initrd_cpio
  do_enable_sftp
  do_patch_features
  do_remove_root_password
  #do_create_emergency_script
  #do_run_emergency_script_in_rcS
  do_package_initrd

  echo "\nDone.\n"
}

main
exit 0
