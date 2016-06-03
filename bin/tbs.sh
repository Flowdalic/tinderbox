#!/bin/sh
#
#set -x

# setup a new tinderbox chroot image
#

# typical call:
#
# $> echo "sudo ~/tb/bin/tbs.sh -A -m stable -i /home/tinderbox/images1 -p default/linux/amd64/13.0/desktop/plasma" | at now


# due to using sudo we need to define the path to $HOME
#
tbhome=/home/tinderbox


#############################################################################
#
# functions
#

# return a (r)andomized (U)SE (f)lag (s)ubset from the set stored in $flags
#
# mask   a flag with a likelihood of 1/m
# or set a flag with a likelihood of 1/s
# else let it be unset
#
function rufs()  {
  m=30
  s=5

  for f in $(echo $flags)
  do
    let "r = $RANDOM % $m"

    if [[ $r -eq 0 ]]; then
      echo -n " -$f"

    elif [[ $r -le $s ]]; then
      echo -n " $f"
    fi
  done
}


function InstallStage3()  {
  # get the current stage3 file name
  #
  wgethost=http://ftp.uni-erlangen.de/pub/mirrors/gentoo
  wgetpath=/releases/amd64/autobuilds
  latest=latest-stage3.txt

  wget --quiet $wgethost/$wgetpath/$latest --output-document=$tbhome/$latest
  if [[ $? -ne 0 ]]; then
    echo " wget failed: $latest"
    exit 4
  fi

  # $name holds the directory name of the chroot image
  # $stage3 holds the full stage3 file name as found in $latest
  #
  if [[ "$profile" = "hardened/linux/amd64" ]]; then
    name="$name-hardened"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  elif [[ "$profile" = "hardened/linux/amd64/no-multilib" ]]; then
    name="$name-hardened-no-multilib"
    stage3=$(grep "^20....../hardened/stage3-amd64-hardened+nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  
  elif [[ "$profile" = "default/linux/amd64/13.0/no-multilib" ]]; then
    name="$name-13.0-no-multilib"
    stage3=$(grep "^20....../stage3-amd64-nomultilib-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  
  elif [[ "$(basename $profile)" = "systemd" ]]; then
    name="$name-$(basename $(dirname $profile))-systemd"
    stage3=$(grep "^20....../systemd/stage3-amd64-systemd-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')

  else
    name="$name-$(basename $profile)"
    stage3=$(grep "^20....../stage3-amd64-20.......tar.bz2" $tbhome/$latest | cut -f1 -d' ')
  fi

  # now complete it with keyword and time stamp
  #
  name="$name-${mask}_$(date +%Y%m%d-%H%M%S)"
  echo " name: $name"

  # download stage3 if not already done
  #
  b=$(basename $stage3)
  f=/var/tmp/distfiles/$b
  if [[ ! -f $f ]]; then
    wget --quiet $wgethost/$wgetpath/$stage3{,.DIGESTS.asc} --directory-prefix=/var/tmp/distfiles || exit 6
  fi

  # do always verify it
  #
  gpg --verify $f.DIGESTS.asc || exit 7

  cd $imagedir  || exit 8
  mkdir $name   || exit 9
  cd $name
  tar xjpf $f   || exit 10
}


function CompilePortageFiles()  {
  # https://wiki.gentoo.org/wiki/Overlay/Local_overlay
  #
  mkdir -p                  usr/local/portage/{metadata,profiles}
  echo 'masters = gentoo' > usr/local/portage/metadata/layout.conf
  echo 'local' >            usr/local/portage/profiles/repo_name
  chown -R portage:portage  usr/local/portage/

  mkdir -p     etc/portage/repos.conf/
  cat << EOF > etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo

[gentoo]
priority = 1

[local]
priority = 2
EOF

  # we'd stay at the "rsync" method for now, "git" pulls in too much deps (gitk etc.)
  #
  cat << EOF > etc/portage/repos.conf/gentoo.conf
[gentoo]
location  = /usr/portage
auto-sync = no
#sync-type = rsync
#sync-uri  = rsync://rsync.de.gentoo.org/gentoo-portage/
EOF

  cat << EOF > etc/portage/repos.conf/local.conf
[local]
location  = /usr/local/portage
masters   = gentoo
auto-sync = no
EOF

  # compile make.conf
  #
  m=etc/portage/make.conf
  chmod a+w $m

  sed -i  -e 's/^CFLAGS="/CFLAGS="-march=native /'    \
          -e 's/^USE=/#USE=/'                         \
          -e 's/^PORTDIR=/#PORTDIR=/'                 \
          -e 's/^PKGDIR=/#PKGDIR=/'                   \
          -e 's#^DISTDIR=.*#DISTDIR="/var/tmp/distfiles"#' $m

  #----------------------------------------
  cat << EOF >> $m
USE="
  sse2 pax_kernel xtpax -cdinstall -oci8 -bindist

$(echo $flags | xargs -s 78 | sed 's/^/  /g')
"

ACCEPT_KEYWORDS="amd64 $( [[ "$mask" = "unstable" ]] && echo -n '~amd64' )"
CPU_FLAGS_X86="aes avx mmx mmxext popcnt sse sse2 sse3 sse4_1 sse4_2 ssse3"
PAX_MARKINGS="XT"

# this is a contribute to my private notebook
#
ALSA_CARDS="hda-intel"
INPUT_DEVICES="evdev synaptics"
VIDEO_CARDS="intel i965"

SSL_BITS=4096

ACCEPT_LICENSE="*"
CLEAN_DELAY=0

# no parallel make, we do prefer to run more images in parallel
#
MAKEOPTS="-j1"

# no "--verbose", it would blow up the size of "emerge --info" over 16KB, which kills b.g.o input window
#
EMERGE_DEFAULT_OPTS="--verbose-conflicts --color=n --nospinner --tree --quiet-build"
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

# no "fail-clean", portage would delete files otherwise before we could pick up them for a bug report
#
FEATURES="xattr preserve-libs parallel-fetch ipc-sandbox network-sandbox test-fail-continue -news"

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa warn error"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$wgethost rsync://mirror.netcologne.de/gentoo/ ftp://sunsite.informatik.rwth-aachen.de/pub/Linux/gor.bytemark.co.uk/gentoo/ rsync://ftp.snt.utwente.nl/gentoo"

EOF
  #----------------------------------------

  # create portage directories and symlink them to tb/data/*
  #
  mkdir usr/portage
  mkdir var/tmp/{distfiles,portage}

  for d in package.{accept_keywords,env,mask,unmask,use} env patches profile
  do
    mkdir     etc/portage/$d 2>/dev/null
    chmod 777 etc/portage/$d
  done

  mkdir tmp/tb  # chr.sh will bind-mount here the host directory

  for d in package.{accept_keywords,env,mask,unmask,use}
  do
    (cd etc/portage/$d; ln -s ../../../tmp/tb/data/$d.common common)
    touch etc/portage/$d/zzz                                          # honeypot for autounmask
  done
  touch       etc/portage/package.mask/self     # avoid a 2nd attempt at this image for failed packages
  chmod a+rw  etc/portage/package.mask/self     # allow tinderbox user to delete entries

  cat << EOF > etc/portage/env/test
FEATURES="test test-fail-continue"
EOF

  cat << EOF > etc/portage/env/splitdebug
CFLAGS="\$CFLAGS -g -ggdb"
CXXFLAGS="\$CFLAGS"
FEATURES="splitdebug"
EOF

  cp -L /etc/hosts /etc/resolv.conf etc/

  cat << EOF > root/.vimrc
set softtabstop=2
set shiftwidth=2
set tabstop=2

:let g:session_autosave = 'no'
EOF

  # fill the package list
  #
  pks=tmp/packages
  qsearch --all --nocolor --name-only --quiet | sort --random-sort > $pks
  echo "sys-kernel/hardened-sources" >> $pks
  echo "@system" >> $pks
  chown tinderbox.tinderbox $pks

  # tweaks requested by devs
  #
  # set XDG_CACHE_HOME=/tmp/xdg in job.sh: https://bugs.gentoo.org/show_bug.cgi?id=567192
  #
  mkdir tmp/xdg
  chmod 700 tmp/xdg
  chown tinderbox:tinderbox tmp/xdg
}


function InstallMandatoryPackages() {
  # install basic packages and those needed by job.sh, configure portage and SMTP
  #

  #----------------------------------------
  cat << EOF > tmp/setup.sh

eselect profile set $profile || exit 1

echo "en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8
" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
. /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
emerge --noreplace net-misc/netifrc

# avoid nano from being depcleaned if another editor is emerged too
#
emerge --noreplace app-editors/nano

emerge sys-apps/elfix || exit 2
migrate-pax -m        || exit 2

# our MTA to get mails out to us
#
emerge mail-mta/ssmtp mail-client/mailx || exit 3

echo "
root=tinderbox@zwiebeltoralf.de
MinUserId=9999
mailhub=mail.zwiebeltoralf.de:465
rewriteDomain=zwiebeltoralf.de
hostname=ms-magpie.zwiebeltoralf.de
UseTLS=YES
" > /etc/ssmtp/ssmtp.conf

# mandatory tools:
#   app-arch/sharutils:         uudecode
#   app-portage/gentoolkit:     equery eshowkw revdep-rebuild
#   app-portage/pfl:            pfl
#   app-portage/portage-utils:  qlop
#
# useful tool(s):
#   app-portage/eix:
#
emerge app-arch/sharutils app-portage/gentoolkit app-portage/pfl app-portage/portage-utils app-portage/eix || exit 3

# at least the very first @world upgrade must not fail
#
emerge --deep --update --newuse --changed-use --with-bdeps=y @world --pretend &> /tmp/world.log || exit 11

exit 0

EOF
  #----------------------------------------

  # installation of mandatory packages should take less than 1/2 hour
  #
  cd - 1>/dev/null

  $(dirname $0)/chr.sh $name '/bin/bash /tmp/setup.sh &> /tmp/setup.log'
  rc=$?
  
  cd $tbhome
  d=$(basename $imagedir)/$name
  
  grep -q "@preserved-rebuild" $d/tmp/setup.log
  if [[ $? -eq 0 ]]; then
    echo "@preserved-rebuild" >> $d/tmp/packages
  fi
  
  grep "^Auth" /etc/ssmtp/ssmtp.conf >> $d/etc/ssmtp/ssmtp.conf

  if [[ $rc -ne 0 ]]; then
    echo
    echo " setup NOT successful (rc=$rc) @ $d"
    echo
    echo " check:   $d/tmp/setup.log"
    echo "          $d/tmp/world.log"
    echo
    echo " test:  sc $d \"emerge --deep --update --newuse --changed-use --with-bdeps=y @world --pretend\""

    exit $rc
  fi

  # create symlink to $HOME *iff* the setup was successful
  #
  ln -s $d || exit 11

  echo
  echo " setup  OK : $d"
  echo
}


#############################################################################
#
# vars
#
name="amd64"  # fixed prefix, append later <profile>, <mask> and <timestamp>

flags="
  aes-ni alisp alsa apache apache2 avcodec avformat avx avx2 btrfs
  bugzilla bzip2 cairo cdb cdda cddb cgi cgoups clang compat consolekit
  corefonts csc cups curl custom-cflags custom-optimization dane dbus debug
  dec_av2 declarative designer dnssec doc dot drmkms dvb dvd ecc egl
  eglfs emacs evdev extra extraengine ffmpeg fontconfig fortran fpm freetds
  ftp gcj gd gif git gles gles2 gnomecanvas gnome-keyring gnuplot gnutls
  gpg graphtft gstreamer gtk gtk2 gtk3 gtkstyle gudev gui gzip haptic
  havege hdf5 help ibus icu imap imlib inifile introspection ipv6 isag
  ithreads jadetex javafx javascript javaxml jpeg kerberos kvm lapack latex
  ldap libinput libkms libvirtd llvm logrotate lzma mad mbox
  mdnsresponder-compat melt midi mikmod minimal minizip mng mod modplug
  mp3 mp4 mpeg mpeg2 mpeg3 mpg123 mpi mssql mta multimedia multitarget mysql
  mysqli ncurses networking nls nscd nss obj objc odbc offensive ogg ois opencv openexr
  opengl openmpi openssl pam pcre16 pdo php pkcs11 plasma png policykit
  postgres postproc postscript printsupport pulseaudio pwquality pyqt4
  python qemu qml qt3support qt4 qt5 rdoc rendering scripts scrypt sddm
  sdl semantic-desktop server smartcard smpeg snmp sockets source spice
  sql sqlite sqlite3 sse4 sse4_1 sse4_2 ssh ssh-askpass ssl ssse3 svg
  swscale system-cairo system-ffmpeg system-harfbuzz system-icu
  system-jpeg system-libevent system-libs system-libvpx system-llvm
  system-sqlite szip tcl tcpd theora thinkpad threads tk tls tools
  tracepath traceroute truetype ufed uml usb usbredir utils uxa v4l v4l2
  vaapi vala vdpau video vim vlc vorbis vpx wav wayland webgl webkit
  webstart widgets wma wxwidgets X x264 x265 xa xcb xetex xinerama xinetd xkb
  xml xmlreader xmp xscreensaver xslt xvfb xvmc xz zenmap ziffy zip zlib
"
# echo $flags | xargs -n 1 | sort -u | xargs -s 76 | sed 's/^/  /g'
#
flags=$(rufs)

Start="n"           # autostart the chroot image (if setup was successful)

let "i = $RANDOM % 2 + 1"
imagedir="$tbhome/images${i}"         # images[12]


#############################################################################
#
# main
#
cd $tbhome

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

while getopts Af:i:m:p: opt
do
  case $opt in
    A)  autostart="y"
        ;;
    f)  if [[ -f "$OPTARG" ]] ; then
          flags="$(cat $OPTARG)"
        else
          flags="$OPTARG"
        fi
        ;;
    i)  imagedir="$OPTARG"
        ;;
    m)  mask="$OPTARG"
        ;;
    p)  profile="$OPTARG"
        ;;
    *)  echo " '$opt' not implemented"
        exit 2
        ;;
  esac
done

if [[ ! "$mask" = "stable" && ! "$mask" = "unstable" ]]; then
  echo " wrong value for mask: $mask"
  exit 3
fi

if [[ ! -d /usr/portage/profiles/$profile ]]; then
  echo " profile unknown: $profile"
  exit 3
fi

if [[ ! -d $imagedir ]]; then
  echo " imagedir does not exist: $imagedir"
  exit 3
fi

InstallStage3
CompilePortageFiles
InstallMandatoryPackages

if [[ "$autostart" = "y" ]]; then
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
  echo "INFO autostart done" >> $d/tmp/packages
fi

exit 0
