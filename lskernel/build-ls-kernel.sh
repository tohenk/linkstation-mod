#!/bin/bash

# Parse parameters
if [ $# -eq 0 ]; then
  BUILD_ALL=1
else
  BUILD_ALL=0
  while [ $# -gt 0 ]; do
    case "$1" in
    -h|--help)
      BUILD_HELP=1
      ;;
    --all)
      BUILD_ALL=1
      ;;
    --clean)
      BUILD_CLEAN=1
      ;;
    --config)
      BUILD_CONFIG=1
      ;;
    --kernel)
      BUILD_KERNEL=1
      ;;
    --dt)
      BUILD_DT=1
      ;;
    --package)
      BUILD_PACKAGE=1
      ;;
    --download)
      BUILD_DOWNLOAD=1
      ;;
    --update)
      BUILD_UPDATE=1
      ;;
    esac
    shift
  done
fi

[ "x$BUILD_HELP" = "x1" ] && {
  echo "Usage:"
  echo "`basename $0` [options...]"
  echo ""
  echo "Options:"
  echo "--all          Build all (clean, config if not configured, kernel, and, DT)"
  echo "--clean        Clean kernel source dir tree"
  echo "--config       Perform kernel cofiguration"
  echo "--kernel       Build kernel images and modules"
  echo "--dt           Build kernel DT"
  echo "--package      Package kernel and modules as tar archive"
  echo "--download     Download kernel source using GIT"
  echo "--update       Update (pull) GIT repository"
  echo ""

  exit 1
}

CDIR=`pwd`
OUTDIR=$CDIR/build
MYDIR=`dirname $0`
MYDIR=`pushd $MYDIR > /dev/null && pwd -P && popd > /dev/null`

. $MYDIR/build-ls-kernel.cfg

KERNEL_DIR=$MYDIR/linux
KERNEL_BOOT_DIR=$KERNEL_DIR/arch/$LS_KERNEL_ARCH/boot
KERNEL_IMAGE=$KERNEL_BOOT_DIR/zImage
KERNEL_DT=$KERNEL_BOOT_DIR/dts/$LS_KERNEL_DT
KERNEL_GIT=${KERNEL_GIT:=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git}

# Download kernel source
[ "x$BUILD_DOWNLOAD" = "x1" ] && {
  [ ! -d "$KERNEL_DIR" ] && {
    mkdir -p "$KERNEL_DIR"
    echo "Cloning from ${KERNEL_GIT}"
    git clone --progress $KERNEL_GIT $KERNEL_DIR
  }
  exit 0
}

# Check kernel source directory
[ ! -d "$KERNEL_DIR" ] && {
  echo "Kernel source directory $KERNEL_DIR not found."
  exit 1
}
[ ! -d "$KERNEL_DIR/.git" ] && {
  echo "Only support building kernel from GIT source."
  exit 1
}

cd "$KERNEL_DIR"

# Update repository
[ "x$BUILD_UPDATE" = "x1" ] && {
  # save current modification
  CLEAN=`git status | grep "working directory clean"`
  [ -z "$CLEAN" ] && git stash save -a
  # switch to master
  git checkout master
  git pull
  exit 1
}

# Checkout version
DO_CHECKOUT=1
KTAG="v$LS_KERNEL_VERSION"
TAG=`git status | grep "$KTAG"`
[ -n "$TAG" ] && {
  RTAG=${TAG#* at }
  [ "$KTAG" = "$RTAG" ] && DO_CHECKOUT=0
}
[ "$DO_CHECKOUT" = "1" ] && {
  TAG_FOUND=0
  # Check for tag
  for TAG in `git tag -l`; do
    [ "$TAG" = "$KTAG" ] && {
      TAG_FOUND=1
      break
    }
  done
  if [ $TAG_FOUND -eq 0 ]; then
    echo "Tag $KTAG not found in the repository."
    exit 1
  else
    echo "Switching to $KTAG."
    CLEAN=`git status | grep "working directory clean"`
    [ -z "$CLEAN" ] && git stash save -a
    git checkout tags/$KTAG
    # copy .config from template
    [ -f "$MYDIR/config/$LS_KERNEL_VERSION" ] && {
      echo "Copying .config from $MYDIR/config/$LS_KERNEL_VERSION..."
      cp "$MYDIR/config/$LS_KERNEL_VERSION" .config
    }
    # apply patches
    [ -d "$MYDIR/patches/$LS_KERNEL_VERSION" ] && {
      for PATCH_FILE in `ls $MYDIR/patches/$LS_KERNEL_VERSION/*.patch`; do
        echo "Applying patch `basename $PATCH_FILE`..."
        git apply $PATCH_FILE
      done
    }
  fi
}

# Build check
[ "x$BUILD_ALL" = "x1" ] && {
  BUILD_CLEAN=1
  BUILD_KERNEL=1
  BUILD_DT=1
}

# Clean everything
[ "x$BUILD_CLEAN" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH clean
}

# Check if .config file has been generated
[ ! -f "$KERNEL_DIR/.config" ] && {
  make ARCH=$LS_KERNEL_ARCH $LS_KERNEL_DEFCONFIG
  BUILD_CONFIG=1
}

# Perform kernel configuration
[ "x$BUILD_CONFIG" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH menuconfig
}

# Compile zImage and modules
[ "x$BUILD_KERNEL" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH CROSS_COMPILE=$LS_KERNEL_CROSS_COMPILE -j4 zImage modules
  [ ! -f "$KERNEL_IMAGE" ] && {
    echo "Kernel image not found, aborting."
    exit 1
  }
}

# Ignore DTB build if no DTS
if [ ! -f "${KERNEL_DT}.dts" ]; then
  BUILD_DT=0
fi

# Compile DTB
[ "x$BUILD_DT" = "x1" ] && {
  make ARCH=$LS_KERNEL_ARCH CROSS_COMPILE=$LS_KERNEL_CROSS_COMPILE ${LS_KERNEL_DT}.dtb
}

# Build package
[ "x$BUILD_PACKAGE" = "x1" ] && {
  # Check for kernel image
  [ ! -f "$KERNEL_IMAGE" ] && {
    echo "Package not built, kernel not found."
    exit 1
  }

  # Check for DTB
  [ -f "${KERNEL_DT}.dts" -a ! -f "${KERNEL_DT}.dtb" ] && {
    echo "Package not built, DTB not found."
    exit 1
  }

  # Prepare outdir
  [ -d "$OUTDIR" ] && rm -rf "$OUTDIR"
  mkdir -p "$OUTDIR" "$OUTDIR/boot"

  # Append DTB first
  [ -f "${KERNEL_DT}.dtb" ] && {
    cat $KERNEL_IMAGE ${KERNEL_DT}.dtb > ${KERNEL_IMAGE}.dtb
    KERNEL_IMAGE=${KERNEL_IMAGE}.dtb
  }

  # Make kernel image
  mkimage -A $LS_KERNEL_ARCH -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n "Linux-$LS_KERNEL_VERSION" -d $KERNEL_IMAGE $OUTDIR/boot/uImage.buffalo

  # Install kernel modules
  make ARCH=$LS_KERNEL_ARCH INSTALL_MOD_PATH=$OUTDIR modules_install

  # Cleanup modules
  for DIR in `cd $OUTDIR/lib/modules && ls`; do
    MOD_DIR=$OUTDIR/lib/modules/$DIR
    [ -d $MOD_DIR ] && {
      rm $MOD_DIR/{source,build}
    }
  done

  # Package rootfs
  cd "$OUTDIR" && tar --no-acls -czf $CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz *
  [ -f "$CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz" ] && echo "Package $CDIR/ls-kernel-${LS_KERNEL_VERSION}.tar.gz successfully created."
}

# Done
cd "$CDIR"