#!/bin/sh

# /bin/busybox
if [ ! -f /bin/busybox~ ]; then
  [ -f busybox-armv7l ] && rm busybox-armv7l
  wget http://busybox.net/downloads/binaries/latest/busybox-armv7l
  if [ -f busybox-armv7l ]; then
    mv /bin/busybox /bin/busybox~
    /bin/busybox~ cp busybox-armv7l /bin/busybox
    /bin/busybox~ chmod +x /bin/busybox
  fi
fi

# /bin/ldd
if [ ! -f /bin/ldd ]; then
  [ -f arm-linux-ldd ] && rm arm-linux-ldd
  wget --no-check-certificate https://stuff.mit.edu/afs/sipb/project/phone-project/bin/arm-linux-ldd
  if [ -f arm-linux-ldd ]; then
    cp arm-linux-ldd /bin/ldd
    sed -i -e 's/ld-linux\.so\.2/ld-linux\.so\.3/' /bin/ldd
    chmod +x /bin/ldd
  fi
fi

# /bin/mkimage
#if [ ! -f /bin/mkimage ]; then
#  [ -f mkimage ] && rm mkimage
#  wget http://downloads.nas-central.org/LSPro_ARM9/DevelopmentTools/CrossToolchains/mkimage
#  if [ -f mkimage ]; then
#    cp mkimage /bin/mkimage
#    chmod +x /bin/mkimage
#  fi
#fi
