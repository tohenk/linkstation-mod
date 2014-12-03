#!/bin/sh

#
# Copyright (C) 2013 Yasunari YAMASHITA. All Rights Reserved.
# Modified for LS421DE by Toha <tohenk@yahoo.com>
#

MYDIR=`dirname $0`
CDIR=`pwd`
DEBINST=$CDIR/debian
OUTDIR=$CDIR/rootfs

. $MYDIR/debootstrap-rootfs.cfg

ARCH=${ARCH:=armhf}
VERSION=${VERSION:=wheezy}
MIRROR=${MIRROR:=http://ftp.us.debian.org/debian}
PACKAGES=${PACKAGES:=}
PACKAGES+=" openssh-server xfsprogs psmisc sudo busybox vim less"

do_debootstrap() {
  date

  /usr/sbin/debootstrap --arch $ARCH $VERSION $DEBINST $MIRROR
}

do_customize() {
  date

  # copy /dev
  #(cd /; tar -cf - dev)|(cd $DEBINST; tar -xf -)
  
  # prepare raid initrd
  [ -d $DEBINST/initrd ] && rm -rf $DEBINST/initrd
  mkdir -p $DEBINST/initrd

  # mount /proc
  chroot $DEBINST mount -t proc /proc proc

  # reconfigure TimeZone
  chroot $DEBINST dpkg-reconfigure tzdata

  local APT=`cat $DEBINST/etc/apt/sources.list | grep "deb-src $MIRROR $VERSION main"`
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
    ) >> $DEBINST/etc/apt/sources.list
  }

  # update package lists
  chroot $DEBINST apt-get update
  chroot $DEBINST apt-get -y -f install
  chroot $DEBINST apt-get -y upgrade
 
  # install & reconfigure locales
  chroot $DEBINST apt-get install locales
  chroot $DEBINST dpkg-reconfigure locales

  # adding missing devices
  chroot $DEBINST apt-get install -y makedev
  chroot $DEBINST /bin/bash -c " 
cd /dev
/sbin/MAKEDEV generic
/sbin/MAKEDEV md"

  # install mdadm
  chroot $DEBINST apt-get --no-install-recommends install mdadm

  # update password of root
  chroot $DEBINST passwd root

  # install some packages
  chroot $DEBINST apt-get -y install $PACKAGES

  # edit /etc/inetd.conf
  #TARGETFILE=$DEBINST/etc/inetd.conf
  #sed \
  #        -e 's/^## telnet/telnet/' \
  #        -i $TARGETFILE

  # add guest user
  chroot $DEBINST adduser --gecos "" guest
  rm -rf $DEBINST/home/guest

  # edit /etc/inittab
  TARGETFILE=$DEBINST/etc/inittab
  sed \
    -e 's/^\([0-9]:[0-9]*:respawn:.*\)$/#\1/' \
    -e '/^#T1/aT0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100' \
    -i $TARGETFILE

  # clean up
  chroot $DEBINST apt-get clean

  # create /etc/adjtime
  (
  echo 0.0 0 0.0
  echo 0
  echo LOCAL
  ) > $DEBINST/etc/adjtime

  # copy ssh authorized_keys 
  if [ -f /root/.ssh/authorized_keys ]; then
    mkdir -p $DEBINST/root/.ssh
    cp /root/.ssh/authorized_keys $DEBINST/root/.ssh/
  fi

  # stopping services
  for SERVICE in mdadm-raid mdadm ssh; do
    chroot $DEBINST /etc/init.d/$SERVICE stop
  done

  # umount /proc
  chroot $DEBINST umount /proc

  # make archive
  cd $DEBINST && tar --numeric-owner -p -czvf $OUTDIR/rootfs_"$VERSION"_"$ARCH"_`date +%y%m%d`.tar.gz *
}

copy_libs() {
  local ROOT=$1
  local TARGET=$2

  cp $MYDIR/libs-cp.sh $ROOT/tmp
  chroot $ROOT /tmp/libs-cp.sh $TARGET
  rm -f $ROOT/tmp/libs-cp.sh
}

prepare_initrd() {
  mkdir -p $DEBINST/initrd/{bin,lib,dev,etc/mdadm,proc,sbin}
  cp -a $DEBINST/dev/{null,console,tty,sd{a,b,c,d}?,md*} $DEBINST/initrd/dev/
 
  cp $DEBINST/bin/busybox $DEBINST/initrd/bin/
  for BIN in sh; do
    cd $DEBINST/initrd/bin && ln -s busybox $BIN
  done;
  cp $DEBINST/sbin/mdadm $DEBINST/initrd/sbin/

  #cp $DEBINST/lib/{libm.so.6,libc.so.6,libgcc_s.so.1,ld-linux.so.3} $DEBINST/initrd/lib/
  #LIBS=$(ldd $DEBINST/initrd/*bin/* | grep -v "^$DEBINST/initrd/" | sed -e 's/.*=> *//'  -e 's/ *(.*//' | sort -u)
  #cd $DEBINST && cp -aL $LIBS $DEBINST/initrd/lib

  local LIBM=`cd "$DEBINST" && find lib -name libm.so.6`
  if [ -n "$LIBM" ]; then
    mkdir -p "`dirname $DEBINST/initrd/$LIBM`"
    cp -aLv "$DEBINST/$LIBM" "$DEBINST/initrd/$LIBM"
  fi

  copy_libs "$DEBINST" /initrd/bin/
  copy_libs "$DEBINST" /initrd/sbin/
  copy_libs "$DEBINST" /initrd/lib
 
  cat > $DEBINST/initrd/linuxrc <<EOF
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
  chmod +x $DEBINST/initrd/linuxrc

  # archive initrd
  cd $DEBINST/initrd && tar --numeric-owner -p -czvf $OUTDIR/initrd_"$VERSION"_"$ARCH"_`date +%y%m%d`.tar.gz *
}

# make working directory
[ -d $DEBINST -a "x$1" = "x--clean" ] && rm -rf $DEBINST

mkdir -p $OUTDIR
if [ ! -d $DEBINST ]; then
  mkdir -p $DEBINST
  do_debootstrap
fi
do_customize
prepare_initrd
