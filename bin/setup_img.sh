#!/bin/bash
# set -x


# setup a new tinderbox image


# helper of ThrowUseFlags()
function IgnoreUseFlags()  {
  grep -v -w -f ~tinderbox/tb/data/IGNORE_USE_FLAGS || true
}

# helper of DryRunWithVaryingUseFlags
function ThrowUseFlags() {
  local n=$1  # pass: up to n-1
  local m=5   # mask: about 20%

  shuf -n $(($RANDOM % $n)) |\
  sort |\
  while read flag
  do
    if [[ $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


# helper of SetOptions()
function GetProfiles() {
  eselect profile list |\
  awk ' { print $2 } ' |\
  grep -e "^default/linux/amd64/17\.1" |\
  grep -v -e '/x32' -e '/selinux' -e '/uclibc' -e 'musl' |\
  cut -f4- -d'/' -s
}


function ThrowCflags()  {
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    # 685160 colon-in-CFLAGS
    cflags="$cflags -falign-functions=32:25:16"
  fi
}


# helper of main()
# the variables here are mostly globals
function SetOptions() {
  cflags_default="-O2 -pipe -march=native -fno-diagnostics-color"
  cflags=""

  # an "y" yields to ABI_X86: 32 64
  multiabi="n"
  # run at most 1 image
  if ! ls -d ~tinderbox/run/*abi32+64* &>/dev/null; then
    if [[ $(($RANDOM % 16)) -eq 0 ]]; then
      multiabi="y"
    fi
  fi

  # prefer a non-running profile
  # however if no one passes the break criteria, then the last entry would make it eventually
  while read profile
  do
    local p=$(tr '/' '_' <<< $profile)
    if ! ls ~tinderbox/run/$p-* &>/dev/null && ! ls -d /run/tinderbox/$p-*.lock &>/dev/null ]]; then
      break
    fi
  done < <(GetProfiles | shuf)

  ThrowCflags

  # check the default USE flag set of choosen profile
  defaultuseflags="n"
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    defaultuseflags="y"
  fi

  testfeature="n"
  # run at most 1 image
#   if ! ls -d ~tinderbox/run/*test* &>/dev/null; then
#     if [[ $(($RANDOM % 16)) -eq 0 ]]; then
#       testfeature="y"
#     fi
#   fi

  science="n"
  # run at most 1 image
  if ! ls -d ~tinderbox/run/*science* &>/dev/null; then
    if [[ $(($RANDOM % 16)) -eq 0 ]]; then
      science="y"
    fi
  fi

  musl="n"
  # no random throwing, Musl is not yet ready for regular scheduling
  if [[ $musl = "y" ]]; then
    cflags="$cflags_default"
    defaultuseflags="y"
    profile="17.0/musl"
    multiabi="n"
    testfeature="n"
  fi

  # best would be to have 1 thread in N running images instead up to N running threads in 1 image
  # OTOH the lifetime of an image with -j 1 is about 35 days running at a 6-core Xeon ...
  jobs=1
}


# helper of CheckOptions()
function checkBool()  {
  var=$1
  val=$(eval echo \$${var})

  if [[ "$val" != "y" && "$val" != "n" ]]; then
    echo " wrong value for variable \$$var: >>$val<<"
    return 1
  fi
}


# helper of main()
function CheckOptions() {
  checkBool "defaultuseflags"
  checkBool "multiabi"
  checkBool "musl"
  checkBool "science"
  checkBool "testfeature"

  if [[ -z "$profile" ]]; then
    echo " profile empty!"
    return 1
  fi

  if [[ ! -d $repodir/gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " wrong profile: >>$profile<<"
    return 1
  fi

  if [[ "$multiabi" = "y" ]]; then
    if [[ $profile =~ "/no-multilib" ]]; then
      echo " ABI_X86 mismatch: >>$profile<<"
      return 1
    fi
  fi

  if [[ ! $jobs =~ ^[0-9].*$ ]]; then
    echo " jobs is wrong: >>${jobs}<<"
    return 1
  fi
}


# helper of UnpackStage3()
function CreateImageName()  {
  # profile[-flavour]-day-time
  name="$(tr '/' '_' <<< $profile)-"
  [[ "$multiabi" = "y" ]]     && name+="_abi32+64"  || true
  [[ "$science" = "y" ]]      && name+="_science"   || true
  [[ "$testfeature" = "y" ]]  && name+="_test"      || true
  [[ $jobs -gt 1 ]]           && name+="_j${jobs}"  || true
  name="$(sed -e 's/-[_-]/-/g' -e 's/-$//' <<< $name)"
  name+="-$(date +%Y%m%d-%H%M%S)"
}


# helper of UnpackStage3()
function CreateImageDir() {
  local l=$(readlink ~tinderbox/img)
  if [[ ! -d ~tinderbox/"$l" ]]; then
    echo "unexpected readlink result '$l'"
    return 1
  fi

  cd ~tinderbox/$l || return 1

  mkdir $name || return 1

  # relative path (eg ./img1) from ~tinderbox
  mnt=$l/$name

  echo " new image: $mnt"
  echo
}


# download, verify and unpack the stage3 file
function UnpackStage3()  {
  local latest="$tbdistdir/latest-stage3.txt"

  for mirror in $gentoo_mirrors
  do
    wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest && break
  done

  if [[ ! -s $latest ]]; then
    echo " empty: $latest"
    return 1
  fi

  local wgeturl="$mirror/releases/amd64/autobuilds"

  case $profile in
    */no-multilib/hardened)   stage3=$(grep "/stage3-amd64-hardened+nomultilib-20.*\.tar\." $latest);;
    */musl/hardened)          stage3=$(grep "/stage3-amd64-musl-hardened-20.*\.tar\." $latest);;
    */hardened)               stage3=$(grep "/stage3-amd64-hardened-20.*\.tar\." $latest);;
    */no-multilib)            stage3=$(grep "/stage3-amd64-nomultilib-20.*\.tar\." $latest);;
    */systemd)                stage3=$(grep "/stage3-amd64-systemd-20.*\.tar\." $latest);;
    */musl)                   stage3=$(grep "/stage3-amd64-musl-vanilla-20.*\.tar\." $latest);;
    *)                        stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest);;
  esac
  local stage3=$(cut -f1 -d' ' -s <<< $stage3)

  if [[ -z "$stage3" || "$stage3" =~ [[:space:]] ]]; then
    echo " can't get stage3 filename for profile '$profile' in $latest"
    return 1
  fi

  local f=$tbdistdir/${stage3##*/}
  if [[ ! -s $f || ! -f $f.DIGESTS.asc ]]; then
    date
    echo " downloading $f ..."
    wget --connect-timeout=10 --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbdistdir || return 1
  fi

  date
  echo " getting signing key ..."
  # use the Gentoo key server, but be relaxed if it doesn't answer
  gpg --keyserver hkps://keys.gentoo.org --recv-keys 534E4209AB49EEE1C19D96162C44695DB9F6043D || true

  date
  echo " verifying $f ..."
  gpg --quiet --verify $f.DIGESTS.asc || return 1
  echo

  CreateImageName
  CreateImageDir

  date
  cd $name
  echo " untar'ing $f ..."
  tar -xpf $f --same-owner --xattrs || return 1
  echo
}


# configure image specific repositories (either being bind mounted or local)
function addRepoConf()  {
  local reponame=$1
  local priority=$2
  local location=${3:-$repodir/$reponame}

  cat << EOF > ./etc/portage/repos.conf/$reponame.conf
[$reponame]
location = $location
priority = $priority

EOF
}


function CompileRepoFiles()  {
  mkdir -p ./etc/portage/repos.conf/

  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo
auto-sync = no

EOF
  # the "local" repository for this particular image
  mkdir -p                  ./$repodir/local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repodir/local/metadata/layout.conf
  echo 'local'            > ./$repodir/local/profiles/repo_name

  addRepoConf "gentoo" "10"
  [[ "$musl" = "y" ]]     && addRepoConf "musl"     "30"  || true
  [[ "$science" = "y" ]]  && addRepoConf "science"  "40"  || true
  addRepoConf "tinderbox" "90" "/mnt/tb/data/portage"
  addRepoConf "local" "99"
}


# compile make.conf
function CompileMakeConf()  {
  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C
NOCOLOR="true"
GCC_COLORS=""
PORTAGE_TMPFS="/dev/shm"

CFLAGS="$cflags_default $cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags_default"
FFLAGS="\${FCFLAGS}"

LDFLAGS="\${LDFLAGS} -Wl,--defsym=__gentoo_check_ldflags__=0"
$([[ ! $profile =~ "/hardened" ]] && echo 'PAX_MARKINGS="none"' || true)

ACCEPT_KEYWORDS="~amd64"

# no re-distribution nor any "usage", just QA
ACCEPT_LICENSE="*"

# just tinderboxing, no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

FEATURES="cgroup xattr -collision-protect -news"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n --with-bdeps=y"

CLEAN_DELAY=0
NOCOLOR=true

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="$gentoo_mirrors"

EOF

  # the "tinderbox" user must be a member of group "portage"
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf
}


# helper of CompilePortageFiles()
function cpconf() {
  for f in $*
  do
    # eg.: .../package.unmask.??common -> package.unmask/??common
    read -r a b c <<<$(tr '.' ' ' <<< ${f##*/})
    cp $f ./etc/portage/"$a.$b/$c"
  done
}


# create portage and tinderbox related directories + files
function CompilePortageFiles()  {
  mkdir -p ./mnt/{repos,tb/data,tb/sdata} ./var/tmp/{portage,tb,tb/logs} ./var/cache/distfiles

  chgrp portage ./var/tmp/tb
  chmod ug+rwx  ./var/tmp/tb

  for d in package.{accept_keywords,env,mask,unmask,use} env
  do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir       ./etc/portage/$d
    fi
    chmod 775     ./etc/portage/$d
    chgrp portage ./etc/portage/$d
  done

  touch       ./etc/portage/package.mask/self     # filled with failed packages of the particular image
  chmod a+rw  ./etc/portage/package.mask/self

  echo 'FEATURES="test"'                          > ./etc/portage/env/test
  echo 'FEATURES="-test"'                         > ./etc/portage/env/notest

  # re-try a failed package with "test" again (to preserve the same dep tree as before) but continue even if the test phase fails
  echo 'FEATURES="test-fail-continue"'            > ./etc/portage/env/test-fail-continue

  # re-try w/o sandbox'ing
  echo 'FEATURES="-sandbox -usersandbox"'         > ./etc/portage/env/nosandbox

  # save CPU cycles with a cron job like:
  # @hourly  sort -u ~tinderbox/run/*/etc/portage/package.env/cflags_default 2>/dev/null > /tmp/cflagsknown2fail; for i in ~/run/*/etc/portage/package.env/; do cp /tmp/cflagsknown2fail $i; done
  cat <<EOF                                       > ./etc/portage/env/cflags_default
CFLAGS="$cflags_default"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="\${CFLAGS}"
FFLAGS="\${CFLAGS}"

EOF

  cat << EOF                                      > ./etc/portage/env/jobs
EGO_BUILD_FLAGS="-p ${jobs}"
GO19CONCURRENTCOMPILATION=0
GOMAXPROCS="${jobs}"
MAKEOPTS="-j ${jobs}"
OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=${jobs}
RUSTFLAGS="-C codegen-units=${jobs}$([[ $musl = "y" ]] && echo " -C target-feature=-crt-static" || true)"
RUST_TEST_THREADS=${jobs}
RUST_TEST_TASKS=${jobs}

EOF

  echo '*/*  jobs' > ./etc/portage/package.env/00jobs

  if [[ $profile =~ '/systemd' ]]; then
    cpconf ~tinderbox/tb/data/package.*.??systemd
  fi

  cpconf ~tinderbox/tb/data/package.*.??common

  if [[ "$multiabi" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.??abi32+64
  fi

  if [[ "$testfeature" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.*test
  else
    # overrule any IUSE=+test
    echo "*/*  notest" > ./etc/portage/package.env/12notest
  fi

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/99cpuflags

  # give Firefox, Thunderbird et al. a chance
  if [[ $(($RANDOM % 8)) -eq 0 ]]; then
    cpconf ~tinderbox/tb/data/package.use.30misc
  fi

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  # use local host DNS resolver
  cat << EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1

EOF

  local h=$(hostname)
  cat << EOF > ./etc/hosts
127.0.0.1 localhost $h.localdomain $h
::1       localhost $h.localdomain $h

EOF

  # avoid interactive question in vim
  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0

EOF
}


# /var/tmp/tb/backlog     : filled  once by setup_img.sh
# /var/tmp/tb/backlog.1st : filled  once by setup_img.sh, job.sh and update_backlog.sh update it
# /var/tmp/tb/backlog.upd : updated      by update_backlog.sh
function CreateBacklog()  {
  local bl=./var/tmp/tb/backlog

  touch                   $bl{,.1st,.upd}
  chmod 664               $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # requested by Whissi, this is an alternative mysql engine
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

# the depclean here must not fail
# the 2nd @{system,world} is made due to the long runtime of the initial one and might BTW clean a failed state
  cat << EOF >> $bl.1st
sys-kernel/gentoo-sources
@world
@system
%emerge --depclean --changed-use
app-portage/pfl
@world
@system
%emerge --deep=0 sys-apps/portage
EOF

  # update GCC first
  #   =         : do not update the current (slotted) version - that will be removed immediately afterwards
  # dev-libs/*  : avoid a rebuild of GCC in @world later caused by an update or rebuild of these deps
  echo "%emerge --deep=0 -uU =\$(portageq best_visible / gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st

  if [[ $profile =~ "/systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $bl.1st
  fi
}


# - configure locales, timezone etc.
# - install and configure tools used in job.sh
#     <package>                   <command>
#     app-portage/portage-utils   qatom
#     mail-*/*                    ssmtp, mail
# - switch to the desired profile
# - fill backlog
function CreateSetupScript()  {
  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/sh
# set -x

# no "-u" b/c "source /etc/profile" would fail otherwise
set -ef

export GCC_COLORS=""

date
echo "#setup rsync" | tee /var/tmp/tb/task

                         rsync --archive --cvs-exclude /mnt/repos/gentoo   $repodir/
[[ $musl = "y" ]]     && rsync --archive --cvs-exclude /mnt/repos/musl     $repodir/  || true
[[ $science = "y" ]]  && rsync --archive --cvs-exclude /mnt/repos/science  $repodir/  || true

date
echo "#setup configure" | tee /var/tmp/tb/task

echo "$name" > /etc/conf.d/hostname
useradd -u $(id -u tinderbox) tinderbox

if [[ ! $musl = "y" ]]; then
  cat << EOF2 >> /etc/locale.gen
# by \$0 at \$(date)
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8

EOF2

  locale-gen -j ${jobs}
  eselect locale set C.UTF-8
fi

env-update
source /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

# date
# echo "#update stage3" | tee /var/tmp/tb/task
# emerge -u --changed-use @world --keep-going=y --exclude sys-devel/gcc --exclude sys-libs/glibc || true
# locale-gen -j ${jobs}

date
env-update
source /etc/profile

# emerge ssmtp separately before mailx b/c the later would pull in a different MTA if none is found
echo "#setup tools" | tee /var/tmp/tb/task
emerge -u mail-mta/ssmtp
emerge -u mail-client/mailx
emerge -u app-portage/portage-utils

eselect profile set --force default/linux/amd64/$profile
if [[ $testfeature = "y" ]]; then
  echo "*/*  test" >> /etc/portage/package.env/11dotest
fi

date
echo "#setup backlog" | tee /var/tmp/tb/task
# sort -u is needed if the same package is in 2 or more repos
qsearch --all --nocolor --name-only --quiet | sort -u | shuf > /var/tmp/tb/backlog

# the very last step: create symlink(s) to r-o bind mounted files
(cd /etc/ssmtp && ln -sf ../../mnt/tb/sdata/ssmtp.conf)

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


function RunSetupScript() {
  date
  echo " run setup script ..."
  cd ~tinderbox/
  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > $mnt/var/tmp/tb/setup_wrapper.sh

  if ! nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s "$mnt/var/tmp/tb/setup_wrapper.sh"; then
    local rc=1
    echo -e "$(date)\n setup was NOT successful (rc=$rc) @ $mnt\n"
    tail -v -n 200 $mnt/var/tmp/tb/setup.sh.log
    echo
    return $rc
  fi
  sed -i -e 's,EMERGE_DEFAULT_OPTS=",EMERGE_DEFAULT_OPTS="--deep ,g'  $mnt/etc/portage/make.conf
}


# the USE flags must do not yield to circular or other non-resolvable dependencies for the very first @world
function DryRunOnce() {
  if ! nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/dryrun_wrapper.sh; then
    local rc=1
    echo -e "\n$(date)\n dry run was NOT successful (rc=$rc):\n"
    tail -v -n 200 $mnt/var/tmp/tb/dryrun.log
    echo
    return $rc
  fi
}


function PrintUseFlags() {
  xargs -s 73 | sed -e '/^$/d' | sed -e "s,^,*/*  ,g"
}


function DryRunWithVaryingUseFlags() {
  local attempt=0
  local max_attempts=99

  while [[ : ]]
  do
    echo

    ((attempt=attempt+1))
    date
    echo "dryrun $attempt#$max_attempts ==========================================================="
    echo
    echo "#setup dryrun $attempt#$max_attempts" > $mnt/var/tmp/tb/task

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/desc/l10n.desc |\
    cut -f1 -d' ' -s |\
    shuf -n $(($RANDOM % 10)) |\
    sort |\
    xargs |\
    xargs -I {} --no-run-if-empty printf "%s %s\n" "*/*  L10N: -* {}" > $mnt/etc/portage/package.use/21thrown_l10n_from_profile

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/use.desc |\
    cut -f1 -d' ' -s |\
    IgnoreUseFlags |\
    ThrowUseFlags 100 |\
    PrintUseFlags > $mnt/etc/portage/package.use/22thrown_global_use_flags_from_profile

    grep -h 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    cut -f2 -d'"' -s |\
    sort -u |\
    IgnoreUseFlags |\
    ThrowUseFlags 100 |\
    PrintUseFlags > $mnt/etc/portage/package.use/23thrown_global_use_flags_from_metadata

    grep -Hl 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    shuf -n $(($RANDOM % 600)) |\
    sort |\
    while read file
    do
      pkg=$(cut -f6-7 -d'/' <<< $file)
      grep -h 'flag name="' $file |\
      cut -f2 -d'"' -s |\
      IgnoreUseFlags |\
      ThrowUseFlags 8 |\
      xargs |\
      xargs -I {} --no-run-if-empty printf "%-50s %s\n" "$pkg" "{}"
    done > $mnt/etc/portage/package.use/24thrown_package_use_flags

    DryRunOnce && break

    if [[ $attempt -ge $max_attempts ]]; then
      echo -e "\n$(date)\ntoo much attempts, giving up\n"
      exit 2
    fi

  done
}


#############################################################################
#
# main
#
set -eu

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

date
echo " $0 started"
echo

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  echo "   $# additional args are given: '${@}'"
  echo
fi

repodir=/var/db/repos
tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s)

autostart="y"
SetOptions

while getopts a:c:d:j:m:p:r:s:t: opt
do
  case $opt in
    a)  autostart="$OPTARG"         ;;
    c)  cflags="$OPTARG"            ;;
    d)  mnt="$OPTARG"
        DryRunWithVaryingUseFlags
        exit 0
        ;;
    j)  jobs="$OPTARG"              ;;
    m)  multiabi="$OPTARG"          ;;
    p)  profile="$OPTARG"           ;;
    r)  defaultuseflags="$OPTARG"   ;;
    s)  science="y"                 ;;
    t)  testfeature="$OPTARG"       ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog
CreateSetupScript
RunSetupScript

echo
echo 'emerge --update --newuse --changed-use --backtrack=30 --pretend @world &> /var/tmp/tb/dryrun.log' > $mnt/var/tmp/tb/dryrun_wrapper.sh
if [[ "$defaultuseflags" = "y" ]]; then
  DryRunOnce
else
  DryRunWithVaryingUseFlags
fi

echo -e "\n$(date)\n  setup OK"
cd ~tinderbox/run
ln -s ../$mnt

if [[ $autostart = "y" ]]; then
  echo
  su - tinderbox -c "${0%/*}/start_img.sh $name"
fi
