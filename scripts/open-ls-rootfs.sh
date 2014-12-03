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

MYDIR=`dirname $0`
ROOT=`pwd`
OUTDIR=$ROOT/out
TMP=$ROOT/tmp
ORIGINAL=$TMP/ORIG
ROOTFS=$TMP/ROOTFS
ROOTFS_IMG_NAME=hddrootfs.img
ROOTFS_FILE_NAME=hddrootfs.buffalo.updated
FIRMWARE=$1

. $MYDIR/ls-functions.sh

do_prep_dirs() {
  show_msg "Preparing directories"
  local DIRS="$ORIGINAL $ROOTFS"
  for D in $DIRS; do
    clean_dir "$D"
  done
  mkdir -p "$OUTDIR"
}

do_unpack_firmware() {
  show_msg "Unpacking firmware"
  ROOTFS_IMG=`unpack_firmware "$TMP" "$FIRMWARE" "$ROOTFS_IMG_NAME"`
  if [ -n "$ROOTFS_IMG" ]; then
    show_info "Found ROOTFS image: $ROOTFS_IMG."
  else
    show_info "No ROOTFS image found! May be it not a valid LinkStation firmware.\n"
  fi
}

do_unpack_rootfs() {
  show_msg "Unpacking ROOTFS image"
  PASSWORD=`unpack_buffalo_image "$ORIGINAL" "$ROOTFS_IMG"`
  if [ -n "$PASSWORD" ]; then
    show_info "Using password $PASSWORD."
  else
    show_info "Can't unpack ROOTFS image, no password matched.\n"
  fi
}

do_extract_rootfs() {
  show_msg "Extracting ROOTFS"
  extract_rootfs "$ROOTFS" "$ORIGINAL/$ROOTFS_FILE_NAME"
}

do_remove_root_password() {
  show_msg "Removing root password"
  INITFILE="$ROOTFS/root/.files/initfile.tar.gz"
  INITFILE_NEW="$ROOTFS/root/.files/new.initfile.tar.gz"
  if [ -f "$INITFILE" ]; then
    show_info "Removing root password from initfile backup."
    INITFILE_TMP=$TMP/INITFILE
    extract_rootfs "$INITFILE_TMP" "$INITFILE"
    remove_root_password "$INITFILE_TMP/etc/shadow"
    package_rootfs "$INITFILE_TMP" "$INITFILE_NEW"
    mv "$INITFILE_NEW" "$INITFILE"
  fi
  show_info "Removing root password from shadow file."
  remove_root_password "$ROOTFS/etc/shadow" "$ROOTFS/etc/shadow~~"
  chmod 0644 "$ROOTFS/etc/shadow"
}

do_create_emergency_script() {
  show_msg "Creating emergency script service"
  local EMERG_SCRIPT="$ROOTFS/etc/rc.d/extensions.d/S00_emergency.sh"
  emergency_script >$EMERG_SCRIPT
  chmod 0755 $EMERG_SCRIPT
}

do_allow_root_login() {
  show_msg "Allowing root login via telnet and ssh"
  # Open telnet
  echo "telnet	stream	tcp	nowait	root	/usr/local/sbin/telnetd	/usr/local/sbin/telnetd" >> "$ROOTFS/etc/inetd.conf"
  #sed -i -e 's/#telnet/telnet/' "$ROOTFS/etc/inetd.conf"
  #if [ ! -f "$ROOTFS/usr/sbin/telnetd" ]; then
  #  cd "$ROOTFS/usr/sbin" && ln -s ../../bin/busybox telnetd
  #fi
  # Allow root login via ssh
  sed -i -e 's/#PermitRootLogin/PermitRootLogin/' "$ROOTFS/etc/sshd_config"
  sed -i -e 's/#StrictModes yes/StrictModes yes/' "$ROOTFS/etc/sshd_config"
  sed -i -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' "$ROOTFS/etc/sshd_config"
  sed -i -e 's/#UsePAM no/UsePAM no/' "$ROOTFS/etc/sshd_config"
  # Patch sshd.sh
  #sed -i -e 's/`which sshd`/\/usr\/sbin\/sshd/' "$ROOTFS/etc/init.d/sshd.sh"
  sed -i -e 's/\[ "${SUPPORT_SFTP}" = "0" \]/\[ `\/bin\/false` \]/' "$ROOTFS/etc/init.d/sshd.sh"
  # Start sshd
  SSHD=`find $ROOTFS/etc/rc.d/extensions.d -name '*sshd.sh' 2>/dev/null`
  if [ "$?" -ne 0 ] || [ -z "$SSHD" ]; then
    show_info "Enabling SSHD service."
    cd "$ROOTFS/etc/rc.d/extensions.d" && ln -s ../../init.d/sshd.sh S99_sshd.sh
  fi
}

do_fix_su_binary() {
  show_msg "Fixing su binary"
  mv "$ROOTFS/bin/su" "$ROOTFS/bin/su~"
  cd "$ROOTFS/bin" && ln -s busybox su
}

do_correct_permissions() {
  show_msg "Correcting permissions"
  chmod 6555 "$ROOTFS/bin/su"
  chmod 0644 "$ROOTFS/etc/profile"
}

do_correct_pam_modules() {
  show_msg "Correcting pam modules"
  cd "$ROOTFS/lib/security" && ln -s pam_unix.so pam_unix_auth.so
  cd "$ROOTFS/lib/security" && ln -s pam_unix.so pam_unix_acct.so
  cd "$ROOTFS/lib/security" && ln -s pam_unix.so pam_unix_passwd.so
  cd "$ROOTFS/lib/security" && ln -s pam_unix.so pam_unix_session.so
}

do_add_executables() {
  show_msg "Adding executables"
  for ARCHIVE in `ls -1 $ROOT/data/*.tar.gz 2>/dev/null`;
  do
    show_info "Adding from $ARCHIVE."
    tar --numeric-owner -p -xzf "$ARCHIVE" -C "$ROOTFS"
  done
}

do_add_ssh_keys() {
  show_msg "Adding ssh key"
  SSH_DIR="$ROOTFS/root/.ssh"
  AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
  for KEY in `ls -1 $ROOT/data/*.key 2>/dev/null`; do
    show_info "Adding key $KEY."
    mkdir -p "$SSH_DIR"
    if [ -f "$AUTHORIZED_KEYS" ]; then
      echo "" >> "$AUTHORIZED_KEYS"
    fi
    cat $KEY >> "$AUTHORIZED_KEYS"
  done
}

do_package_rootfs() {
  show_msg "Package ROOTFS"
  package_rootfs "$ROOTFS" "$OUTDIR/$ROOTFS_FILE_NAME"
  pack_firmware "$OUTDIR" "$ROOTFS_IMG_NAME" "$ROOTFS_FILE_NAME" "$PASSWORD"
  if [ -f "$OUTDIR/$ROOTFS_IMG_NAME" ]; then
    show_info "Opened ROOTFS image saved in $OUTDIR/$ROOTFS_IMG_NAME."
  fi
}

main() {
  echo "Opening stock firmware ROOTFS of $FIRMWARE."

  FNAME=`basename $FIRMWARE`
  FEXT="${FNAME##*.}"

  do_prep_dirs
  if [ "$FEXT" = "img" ]; then
    ROOTFS_IMG=$FIRMWARE
    ROOTFS_IMG_NAME=$FNAME
  else
    do_unpack_firmware
  fi
  if [ ! -f "$ROOTFS_IMG" ]; then
    exit 1;
  fi
  do_unpack_rootfs
  if [ -z "$PASSWORD" ]; then
    exit 1;
  fi
  do_extract_rootfs
  do_remove_root_password
  do_allow_root_login
  do_add_ssh_keys
  do_create_emergency_script
  #do_fix_su_binary
  #do_correct_permissions
  #do_correct_pam_modules
  #do_add_executables
  do_package_rootfs

  echo "\nDone.\n"
}

main
exit 0
