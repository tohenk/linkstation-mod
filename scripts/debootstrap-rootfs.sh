#!/bin/bash

#
# Copyright (C) 2013 Yasunari YAMASHITA. All Rights Reserved.
# Copyright (C) 2015 Toha <tohenk@yahoo.com>
#
# Modified for LS421DE by Toha <tohenk@yahoo.com>
#

MYDIR=`dirname $0`
MYDIR=`pushd $MYDIR > /dev/null && pwd -P && popd > /dev/null`
CDIR=`pwd`
DEBINST=$CDIR/debian
OUTDIR=$CDIR/rootfs

. $MYDIR/ls-functions.sh
. $MYDIR/debootstrap-rootfs.cfg

ARCH=${ARCH:=armhf}
VERSION=${VERSION:=wheezy}
MIRROR=${MIRROR:=http://ftp.us.debian.org/debian}
PACKAGES=${PACKAGES:=}
PACKAGES+=" aptitude openssh-server xfsprogs psmisc sudo busybox vim less"
USER=${USER:=guest}

MYSHELL=/bin/bash
DEBINST_BASE=$DEBINST/base
DEBINST_SYSTEM=$DEBINST/system
DEBINST_PACKAGE=$DEBINST/base.tar.gz
ROOTFS_PACKAGE=$OUTDIR/rootfs_${VERSION}_${ARCH}_`date +%y%m%d`.tar.gz
INITRD_PACKAGE=$OUTDIR/initrd_${VERSION}_${ARCH}_`date +%y%m%d`.tar.gz

do_debootstrap() {
  show_msg "Debootstrapping $VERSION on `date`"

  if [ -f $DEBINST_PACKAGE ]; then
    show_info "Skipping debootstrap, already done..."
    return 0
  fi

  if [ -d $DEBINST_BASE ]; then
    rm -rf $DEBINST_BASE
  fi
  mkdir -p $DEBINST_BASE
  debootstrap --arch $ARCH $VERSION $DEBINST_BASE $MIRROR
  if [ $? -eq 0 ]; then
    cd $DEBINST_BASE && tar --numeric-owner -p -czf $DEBINST_PACKAGE *
    rm -rf $DEBINST_BASE
    show_info "Done $DEBINST_PACKAGE..."
    return 0
  fi
  return 1
}

do_customize() {
  show_msg "Customize $VERSION on `date`"

  if [ ! -f $DEBINST_PACKAGE ]; then
    show_info "Aborting customization, debootstrap package not found..."
    return 1
  fi

  # try unmount procfs
  if [ -d $DEBINST_SYSTEM/proc ]; then
    umount $DEBINST_SYSTEM/proc 2> /dev/null
  fi

  # clean everything
  if [ -d $DEBINST_SYSTEM ]; then
    rm -rf $DEBINST_SYSTEM
  fi
  mkdir -p $DEBINST_SYSTEM

  # extract deboostrap package
  tar -xf $DEBINST_PACKAGE -C $DEBINST_SYSTEM

  # copy /dev
  #(cd /; tar -cf - dev)|(cd $DEBINST_SYSTEM; tar -xf -)
  
  # prepare raid initrd
  [ -d $DEBINST_SYSTEM/initrd ] && rm -rf $DEBINST_SYSTEM/initrd
  mkdir -p $DEBINST_SYSTEM/initrd

  # mount /proc
  chroot $DEBINST_SYSTEM mount -t proc none /proc

  local APT=`cat $DEBINST_SYSTEM/etc/apt/sources.list | grep "deb-src $MIRROR $VERSION main"`
  [ -z "$APT" ] && {
    # edit /etc/apt/sources.list
    (
    echo deb-src $MIRROR $VERSION main
    echo
    echo deb $MIRROR $VERSION-updates main
    echo deb-src $MIRROR $VERSION-updates main
    echo
    echo deb $MIRROR $VERSION-proposed-updates main
    echo deb-src $MIRROR $VERSION-proposed-updates main
    echo
    echo deb http://security.debian.org/ $VERSION/updates main
    echo deb-src http://security.debian.org/ $VERSION/updates main
    ) >> $DEBINST_SYSTEM/etc/apt/sources.list
  }

  # update package lists
  chroot $DEBINST_SYSTEM apt-get update
 
  # install & reconfigure locales
  chroot $DEBINST_SYSTEM $MYSHELL -c "
export LANG=C
apt-get install locales
dpkg-reconfigure locales"

  # reconfigure TimeZone
  chroot $DEBINST_SYSTEM dpkg-reconfigure tzdata

  # forced upgrade
  chroot $DEBINST_SYSTEM apt-get -y -f install
  chroot $DEBINST_SYSTEM apt-get -y upgrade

  # adding missing devices
  chroot $DEBINST_SYSTEM apt-get install -y makedev
  # workaround in case armhf not supported by MAKEDEV
  sed -i -e "s/arm|armeb|armel/arm|armeb|armel|armhf/g" $DEBINST_SYSTEM/sbin/MAKEDEV
  chroot $DEBINST_SYSTEM $MYSHELL -c "
cd /dev
MAKEDEV generic
MAKEDEV md"

  # install mdadm
  chroot $DEBINST_SYSTEM apt-get --no-install-recommends install mdadm

  # update password of root
  chroot $DEBINST_SYSTEM passwd root

  # install some packages
  chroot $DEBINST_SYSTEM apt-get -y install $PACKAGES

  # edit /etc/inetd.conf
  #TARGETFILE=$DEBINST_SYSTEM/etc/inetd.conf
  #sed \
  #        -e 's/^## telnet/telnet/' \
  #        -i $TARGETFILE

  # add user
  chroot $DEBINST_SYSTEM adduser --gecos "$USER" $USER
  rm -rf $DEBINST_SYSTEM/home/$USER

  # edit /etc/inittab
  TARGETFILE=$DEBINST_SYSTEM/etc/inittab
  if [ -f $TARGETFILE ]; then
    sed \
      -e 's/^\([0-9]:[0-9]*:respawn:.*\)$/#\1/' \
      -e '/^#T1/aT0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100' \
      -i $TARGETFILE
  fi

  # clean up
  chroot $DEBINST_SYSTEM apt-get clean

  # create /etc/adjtime
  (
  echo 0.0 0 0.0
  echo 0
  echo LOCAL
  ) > $DEBINST_SYSTEM/etc/adjtime

  # copy ssh authorized_keys 
  if [ -f /root/.ssh/authorized_keys ]; then
    mkdir -p $DEBINST_SYSTEM/root/.ssh
    cp /root/.ssh/authorized_keys $DEBINST_SYSTEM/root/.ssh/
  fi

  # stopping services
  for SERVICE in mdadm-raid mdadm ssh; do
    chroot $DEBINST_SYSTEM /etc/init.d/$SERVICE stop
  done

  # umount /proc
  chroot $DEBINST_SYSTEM umount /proc

  # make archive
  cd $DEBINST_SYSTEM && tar --numeric-owner -p -czf $ROOTFS_PACKAGE *

  show_info "Done $ROOTFS_PACKAGE..."

  return 0
}

copy_libs() {
  local ROOT=$1
  local TARGET=$2

  cp $MYDIR/libs-cp.sh $ROOT/tmp
  chroot $ROOT /tmp/libs-cp.sh $TARGET
  rm -f $ROOT/tmp/libs-cp.sh
}

prepare_initrd() {
  show_msg "Creating $VERSION INITRD on `date`"

  if [ ! -f $DEBINST_PACKAGE ]; then
    show_info "Aborting INITRD, debootstrap package not found..."
    return 1
  fi

  mkdir -p $DEBINST_SYSTEM/initrd/{bin,lib,dev,etc/mdadm,proc,sbin}
  cp -a $DEBINST_SYSTEM/dev/{null,console,tty,sd{a,b,c,d}?,md*} $DEBINST_SYSTEM/initrd/dev/
 
  cp $DEBINST_SYSTEM/bin/busybox $DEBINST_SYSTEM/initrd/bin/
  for BIN in sh; do
    cd $DEBINST_SYSTEM/initrd/bin && ln -s busybox $BIN
  done
  cp $DEBINST_SYSTEM/sbin/mdadm $DEBINST_SYSTEM/initrd/sbin/

  #cp $DEBINST_SYSTEM/lib/{libm.so.6,libc.so.6,libgcc_s.so.1,ld-linux.so.3} $DEBINST_SYSTEM/initrd/lib/
  #LIBS=$(ldd $DEBINST_SYSTEM/initrd/*bin/* | grep -v "^$DEBINST_SYSTEM/initrd/" | sed -e 's/.*=> *//'  -e 's/ *(.*//' | sort -u)
  #cd $DEBINST_SYSTEM && cp -aL $LIBS $DEBINST_SYSTEM/initrd/lib

  local LIBM=`cd "$DEBINST_SYSTEM" && find lib -name libm.so.6`
  if [ -n "$LIBM" ]; then
    mkdir -p "`dirname $DEBINST_SYSTEM/initrd/$LIBM`"
    cp -aLv "$DEBINST_SYSTEM/$LIBM" "$DEBINST_SYSTEM/initrd/$LIBM"
  fi

  copy_libs "$DEBINST_SYSTEM" /initrd/bin/
  copy_libs "$DEBINST_SYSTEM" /initrd/sbin/
  copy_libs "$DEBINST_SYSTEM" /initrd/lib
 
  cat > $DEBINST_SYSTEM/initrd/linuxrc <<EOF
#!/bin/sh
 
# Mount the /proc and /sys filesystems.
mount -t proc none /proc
mount -t sysfs none /sys
 
echo 'DEVICE /dev/sd??*' > /etc/mdadm/mdadm.conf
mdadm -Eb /dev/sd??* >> /etc/mdadm/mdadm.conf
mdadm -As --force
 
# use /dev/md1 as root
echo "0x901" > /proc/sys/kernel/real-root-dev
# use /dev/md2 as root
# echo "0x902" > /proc/sys/kernel/real-root-dev
# use /dev/sda6 as root
# echo "0x806" > /proc/sys/kernel/real-root-dev
# use /dev/sdb6 as root
# echo "0x822" > /proc/sys/kernel/real-root-dev
 
# Clean up.
umount /proc
umount /sys

exit 0
EOF
  chmod +x $DEBINST_SYSTEM/initrd/linuxrc

  # archive initrd
  cd $DEBINST_SYSTEM/initrd && tar --numeric-owner -p -czf $INITRD_PACKAGE *

  show_info "Done $INITRD_PACKAGE..."

  return 0
}

# make working directory
[ -d $DEBINST -a "x$1" = "x--clean" ] && {
  [ -d $DEBINST_SYSTEM/proc ] && {
    umount $DEBINST_SYSTEM/proc 2> /dev/null
  }
  rm -rf $DEBINST
}
mkdir -p $DEBINST $OUTDIR

for MYCMD in do_debootstrap do_customize prepare_initrd; do
  $MYCMD
  if [ ! $? -eq 0 ]; then
    show_info "Aborted."
    exit 1
  fi
done

exit 0
