#!/bin/bash
# set -x


# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.


# strip away quotes
function stripQuotesAndMore() {
  sed -e 's,['\''‘’"`•],,g' -e 's/\xE2\x80\x98|\xE2\x80\x99//g' # UTF-2018+2019 (left+right single quotation mark)
}


# filter leftovers of ansifilter
function filterPlainPext() {
  perl -wne ' s,\x00,\n,g; s,\r\n,\n,g; s,\r,\n,g; print; '
}


function Mail() {
  local subject=$(stripQuotesAndMore <<< $1 | cut -c1-200 | tr '\n' ' ')
  local content=${2:-}

  if [[ -s $content ]]; then
    echo
    head -n 10000 $content | sed -e 's,^>>>, >>>,'
    echo
  else
    echo -e "$content"
  fi |\
  if ! timeout 60 mail -s "$subject    @ $name" -- ${MAILTO:-tinderbox} &>> /var/tmp/tb/mail.log; then
    echo "$(date) mail timeout, \$subject=$subject \$2=$2" | tee -a /var/tmp/tb/mail.log
    chmod a+rw /var/tmp/tb/mail.log
  fi
}


# http://www.portagefilelist.de
function feedPfl()  {
  if [[ -x /usr/bin/pfl ]]; then
    /usr/bin/pfl &>/dev/null
  fi
}


# this is the end ...
function Finish()  {
  local exit_code=${1:-$?}

  trap - INT QUIT TERM EXIT

  feedPfl

  subject=$(stripQuotesAndMore <<< ${2:-<no subject given>} | tr '\n' ' ' | cut -c1-200)
  if [[ $exit_code -eq 0 ]]; then
    Mail "Finish ok: $subject" "${3:-<no message given>}"
    truncate -s 0 $taskfile
  else
    Mail "Finish NOT ok, exit_code=$exit_code: $subject" "${3:-$tasklog}"
  fi

  rm -f /var/tmp/tb/STOP
  exit $exit_code
}


# helper of getNextTask()
function setTaskAndBacklog()  {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $(($RANDOM % 4)) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    Finish 0 "empty backlogs, $(qlist -Iv | wc -l) packages installed"
  fi

  # move last line of $backlog into $task
  task=$(tail -n 1 $backlog)
  sed -i -e '$d' $backlog
}


function getNextTask() {
  while :
  do
    setTaskAndBacklog

    if [[ -z "$task" || $task =~ ^# ]]; then
      continue  # empty line or comment

    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"
      continue

    elif [[ $task =~ ^STOP ]]; then
      echo "#stopping by task" > $taskfile
      Finish 0 "$task"

    elif [[ $task =~ ^@ || $task =~ ^% ]]; then
      break  # @set or %command

    elif [[ $task =~ ^= ]]; then
      # pinned version, but check validity
      if portageq best_visible / $task &>/dev/null; then
        break
      fi

    else
      if [[ ! "$backlog" = /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<< $task; then
          continue
        fi
      fi

      local best_visible

      if ! best_visible=$(portageq best_visible / $task 2>/dev/null); then
        continue
      fi

      # skip if $task would be downgraded
      local installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        if qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '; then
          continue
        fi
      fi

      # $task is valid
      break
    fi
  done

  echo "$task" | tee -a $taskfile.history $tasklog > $taskfile
}


# helper of CollectIssueFiles
function collectPortageDir()  {
  (cd / && tar -cjpf $issuedir/files/etc.portage.tar.bz2 --dereference etc/portage)
}


# b.g.o. has a limit of 1 MB
function CompressIssueFiles()  {
  for f in $(ls $issuedir/task.log $issuedir/files/* 2>/dev/null | grep -v -F '.bz2')
  do
    if [[ $(wc -c < $f) -gt 1000000 ]]; then
      bzip2 $f
    fi
  done

  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
}


function CreateEmergeHistoryFile()  {
  local ehist=$issuedir/files/emerge-history.txt
  local cmd="qlop --nocolor --verbose --merge --unmerge"

  cat << EOF > $ehist
# This file contains the emerge history got with:
# $cmd
EOF
  ($cmd) &>> $ehist
}


# gather together what's needed for the email and b.g.o.
function CollectIssueFiles() {
  CreateEmergeHistoryFile

  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $tasklog_stripped | grep "\.out"          | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $tasklog_stripped | grep "CMake.*\.log"   | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $tasklog_stripped | sed  "s/txt./txt/"    | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $tasklog_stripped | grep "\.log"          | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $tasklog_stripped                         | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                 $tasklog_stripped | grep "\.log"          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $tasklog_stripped                                  | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach the following file: ' $tasklog_stripped | grep "/LastTest\.log" | awk ' { print $2 } ')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg
  do
    if [[ -f $f ]]; then
      cp $f $issuedir/files
    fi
  done

  if [[ -d "$workdir" ]]; then
    # catch relevant logs
    (
      set -e
      f=/var/tmp/tb/files
      cd "$workdir/.."
      find ./ -name "*.log" \
          -o -name "testlog.*" \
          -o -wholename '*/elf/*.out' \
          -o -wholename '*/softmmu-build/*' \
          -o -name "meson-log.txt" |\
          sort -u > $f
      if [[ -s $f ]]; then
        tar -cjpf $issuedir/files/logs.tar.bz2 \
            --dereference \
            --warning='no-file-removed' \
            --warning='no-file-ignored' \
            --files-from $f 2>/dev/null
      fi
      rm $f
    )

    # additional cmake files
    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null

    # provide the whole temp dir if possible
    (
      set -e
      cd "$workdir/../.."
      if [[ -d ./temp ]]; then
        timeout -s 15 180 tar -cjpf $issuedir/files/temp.tar.bz2 \
            --dereference \
            --warning='no-file-ignored'  \
            --warning='no-file-removed' \
            --exclude='*/go-build[0-9]*/*' \
            --exclude='*/go-cache/??/*' \
            --exclude='*/kerneldir/*' \
            --exclude='*/nested_link_to_dir/*' \
            --exclude='*/testdirsymlink/*' \
            --exclude='*/var-tests/*' \
            ./temp
      fi
    )

    # ICE
    if [[ -f $workdir/gcc-build-logs.tar.bz2 ]]; then
      cp $workdir/gcc-build-logs.tar.bz2 $issuedir/files
    fi
  fi
}


function createAndPrefillIssueDir() {
  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<< $pkg)
  mkdir -p $issuedir/files
  chmod 777 $issuedir # allow to edit title etc. manually

  echo "$repo" > $issuedir/repository   # used by check_bgo.sh
  cp $pkglog  $issuedir/files           # origin, unprocessed
  cp $tasklog $issuedir                 # stripped
}


# get package and logfile names + create the dir
function DerivePkgFromTaskLog() {
  pkg="$(cd /var/tmp/portage; ls -1td */* 2>/dev/null | head -n 1)" # head due to 32/64 multilib variants
  if [[ -z "$pkg" ]]; then # eg. in postinst phase
    pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk ' { print $3 } ')
    if [[ -z "$pkg" ]]; then
      pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f5 -d' ' -s | cut -f1 -d',' -s)
      if [[ -z "$pkg" ]]; then
        pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
        if [[ -z $pkg ]]; then
          return 1
        fi
      fi
    fi
  fi

  pkgname=$(qatom --quiet "$pkg" 2>/dev/null | grep -v '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')

  # double check that the values are ok
  repo=$(portageq metadata / ebuild $pkg repository)
  repo_path=$(portageq get_repo_path / $repo)
  if [[ ! -d $repo_path/$pkgname ]]; then
    Mail "INFO: $FUNCNAME failed to get repo path for: pkg='$pkg'  pkgname='$pkgname'  task='$task'" $tasklog_stripped
    return 1
  fi

  pkglog=$(grep -o -m 1 "/var/log/portage/$(tr '/' ':' <<< $pkgname).*\.log" $tasklog_stripped)
  if [[ ! -f $pkglog ]]; then
    Mail "INFO: $FUNCNAME failed to get package log file: pkg='$pkg'  pkgname='$pkgname'  task='$task'  pkglog='$pkglog'" $tasklog_stripped
    return 1
  fi

  createAndPrefillIssueDir
}


# helper of ClassifyIssue()
function foundCollisionIssue() {
  # get the colliding package name
  local s=$(
    grep -m 1 -A 5 'Press Ctrl-C to Stop' $tasklog_stripped |\
    tee -a  $issuedir/issue |\
    grep -m 1 '::' | tr ':' ' ' | cut -f3 -d' ' -s
  )
  echo "file collision with $s" > $issuedir/title
}


# helper of ClassifyIssue()
function foundSandboxIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/nosandbox 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "nosandbox" >> /etc/portage/package.env/nosandbox
    try_again=1
  fi
  echo "sandbox issue" > $issuedir/title
  head -n 10 $sandb &> $issuedir/issue
}


# helper of ClassifyIssue()
function foundCflagsIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/cflags_default 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "cflags_default" >> /etc/portage/package.env/cflags_default
    try_again=1
  fi
  echo "$1" > $issuedir/title
}


# helper of ClassifyIssue()
function foundGenericIssue() {
    pushd /var/tmp/tb 1>/dev/null

    # run sequential over the pattern in the order they are specified
    # to avoid shell/quoting effects put each pattern in a file and point to that in "grep -m 1 ... -f"
    (
      if [[ -n "$phase" ]]; then
        cat /mnt/tb/data/CATCH_ISSUES.$phase
      fi
      cat /mnt/tb/data/CATCH_ISSUES
    ) | split --lines=1 --suffix-length=2 - x

    for x in ./x??
    do
      if grep -m 1 -a -B 2 -A 4 -f $x $pkglog_stripped > ./issue; then
        mv ./issue $issuedir
        sed -n '3p' $issuedir/issue | stripQuotesAndMore > $issuedir/title # fails if "-B 2" didn't delivered
        break
      fi
    done
    rm -f ./x?? ./issue

    popd 1>/dev/null
}


# helper of ClassifyIssue()
function handleTestPhase() {
  if ! grep -q "=$pkg " /etc/portage/package.env/test-fail-continue 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "test-fail-continue" >> /etc/portage/package.env/test-fail-continue
    try_again=1
  fi

  # tar returns an error if it can't find at least one directory
  # therefore feed only existing dirs to it
  pushd "$workdir" 1>/dev/null
  local dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
  if [[ -n "$dirs" ]]; then
    # the tar here is know to spew things like the obe below so ignore errors
    # tar: ./automake-1.13.4/t/instspc.dir/a: Cannot stat: No such file or directory
    tar -cjpf $issuedir/files/tests.tar.bz2 \
        --exclude="*/dev/*" --exclude="*/proc/*" --exclude="*/sys/*" --exclude="*/run/*" \
        --exclude='*.o' --exclude="*/symlinktest/*" \
        --dereference --sparse --one-file-system --warning='no-file-ignored' \
        $dirs 2>/dev/null
  fi
  popd 1>/dev/null
}


# helper of GotAnIssue()
# get the issue and a descriptive title
function ClassifyIssue() {
  touch $issuedir/{issue,title}

  # "-m 1" because for phase "install" grep might have 2 matches ("doins failed" and "newins failed")
  # "-o" in the 1st grep b/c sometimes perl spews a message into the same line
  phase=$(
    grep -m 1 -o " \* ERROR:.* failed (.* phase):" $pkglog_stripped |\
    grep -Eo '\(.* ' | cut -c2-
  )

  if [[ "$phase" = "test" ]]; then
    handleTestPhase
  fi

  if grep -q -m 1 -F ' * Detected file collision(s):' $pkglog_stripped; then
    foundCollisionIssue

  elif [[ -n $sandb ]]; then # no "-f" b/c it might not exist
    foundSandboxIssue

  # special forced issues
  elif [[ -n "$(grep -m 1 -B 4 -A 1 'sed:.*expression.*unknown option' $pkglog_stripped | tee $issuedir/issue)" ]]; then
    foundCflagsIssue 'ebuild uses colon (:) as a sed delimiter'

  else
    grep -m 1 -A 2 " \* ERROR:.* failed (.* phase):" $pkglog_stripped | tee $issuedir/issue |\
    head -n 2 | tail -n 1 > $issuedir/title
    foundGenericIssue
  fi

  # if the issue file size is too big, then delete the 1st line till it fits
  while :
  do
    read -r lines chars <<< $(wc -l -c < $issuedir/issue)
    if [[ $lines -le 1 || $chars -le 1024 ]]; then
      break
    fi
    sed -i -e "1d" $issuedir/issue
  done
}


# helper of GotAnIssue()
# creates an email containing convenient links and a command line ready for copy+paste
function CompileIssueComment0() {
  emerge -p --info $pkgname &> $issuedir/emerge-info.txt

  cp $issuedir/issue $issuedir/comment0
  cat << EOF >> $issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

EOF

  (
    echo "gcc-config -l:"
    gcc-config -l

    clang --version
    llvm-config --prefix --version
    python -V
    eselect ruby list
    eselect rust list
    java-config --list-available-vms --nocolor
    eselect java-vm list
    ghc --version
    eselect php list cli

    for i in /var/db/repos/*/.git
    do
      cd $i/..
      echo -e "\n  HEAD of ::$(basename $PWD)"
      git show -s HEAD
    done

    echo
    echo "emerge -qpvO $pkgname"
    emerge -qpvO $pkgname | head -n 1
  ) >> $issuedir/comment0 2>/dev/null

  tail -v */etc/portage/package.*/??$keyword >> $issuedir/comment0 2>/dev/null
}

# make world state same as if (succesfully) installed deps were emerged step by step in previous emerges
function PutDepsIntoWorldFile() {
  if grep -q '^>>> Installing ' $tasklog_stripped; then
    emerge --depclean --verbose=n --pretend 2>/dev/null |\
    grep "^All selected packages: "                     |\
    cut -f2- -d':' -s                                   |\
    xargs --no-run-if-empty emerge -O --noreplace &>/dev/null
  fi
}


# helper of GotAnIssue()
# for ABI_X86="32 64" we have two ./work directories in /var/tmp/portage/<category>/<name>
function setWorkDir() {
  workdir=$(fgrep -m 1 " * Working directory: '" $tasklog_stripped | cut -f2 -d"'" -s)
  if [[ ! -d "$workdir" ]]; then
    workdir=$(fgrep -m 1 ">>> Source unpacked in " $tasklog_stripped | cut -f5 -d" " -s)
    if [[ ! -d "$workdir" ]]; then
      workdir=/var/tmp/portage/$pkg/work/${pkg##*/}
      if [[ ! -d "$workdir" ]]; then
        workdir=""
      fi
    fi
  fi
}


function add2backlog()  {
  # no duplicates
  if [[ ! "$(tail -n 1 /var/tmp/tb/backlog.1st)" = "${@}" ]]; then
    echo "${@}" >> /var/tmp/tb/backlog.1st
  fi
}


function finishTitle()  {
  # strip away hex addresses, loong path names, line and time numbers and other stuff
  sed -i  -e 's/0x[0-9a-f]*/<snip>/g'         \
          -e 's/: line [0-9]*:/:line <snip>:/g' \
          -e 's/[0-9]* Segmentation fault/<snip> Segmentation fault/g' \
          -e 's/Makefile:[0-9]*/Makefile:<snip>/g' \
          -e 's,:[[:digit:]]*): ,:<snip>:,g'  \
          -e 's,([[:digit:]]* of [[:digit:]]*),(<snip> of <snip)>,g'  \
          -e 's,[0-9]*[\.][0-9]* sec,,g'      \
          -e 's,[0-9]*[\.][0-9]* s,,g'        \
          -e 's,([0-9]*[\.][0-9]*s),,g'       \
          -e 's/ \.\.\.*\./ /g'               \
          -e 's/___*/_/g'                     \
          -e 's/; did you mean .* \?$//g'     \
          -e 's/(@INC contains:.*)/.../g'     \
          -e "s,ld: /.*/cc......\.o: ,ld: ,g" \
          -e 's,target /.*/,target <snip>/,g' \
          -e 's,(\.text\..*):,(<snip>),g'     \
          -e 's,object index [0-9].*,object index <snip>,g' \
          -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g' \
          -e 's,ninja: error: /.*/,ninja error: .../,' \
          -e 's,:[[:digit:]]*:[[:digit:]]*: ,: ,' \
          -e 's,\*, ,g' \
        $issuedir/title

  # prefix title
  sed -i -e "s,^,${pkg} - ," $issuedir/title
  if [[ $phase = "test" ]]; then
    sed -i -e "s,^,[TEST] ," $issuedir/title
  fi
  if [[ $repo != "gentoo" ]]; then
    sed -i -e "s,^,[$repo overlay] ," $issuedir/title
  fi
  if [[ $keyword = "stable" ]]; then
    sed -i -e "s,^,[stable] ," $issuedir/title
  fi

  sed -i -e 's,  *, ,g' $issuedir/title
  truncate -s "<${1:-130}" $issuedir/title    # b.g.o. limits "Summary" length
}


function IfNewThenSendIssueMail()  {
  if ! grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title; then
    if ! grep -F -q -f $issuedir/title /mnt/tb/data/ALREADY_CATCHED; then
      # wrap cat with echo due to buffered output of cat
      echo "$(cat $issuedir/title)" >> /mnt/tb/data/ALREADY_CATCHED
      echo -e "\n\n    check_bgo.sh ~/img/$name/$issuedir\n\n\n" > $issuedir/body
      cat $issuedir/issue >> $issuedir/body
      Mail "$(cat $issuedir/title)" $issuedir/body
    fi
  fi
}


# analyze the issue
function GotAnIssue()  {
  local fatal=$(grep -m 1 -f /mnt/tb/data/FATAL_ISSUES $tasklog_stripped) || true
  if [[ -n $fatal ]]; then
    Finish 1 "FATAL: $fatal"
  fi

  if grep -q -e "Exiting on signal" -e " \* The ebuild phase '.*' has been killed by signal" $tasklog_stripped; then
    Finish 1 "KILLED"
  fi

  pkglog_stripped=$issuedir/$(basename $pkglog)
  filterPlainPext < $pkglog > $pkglog_stripped
  setWorkDir
  CollectIssueFiles
  collectPortageDir
  CompressIssueFiles

  ClassifyIssue
  finishTitle
  CompileIssueComment0

  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/

  if grep -q -e 'error: perl module .* required' -e 'Cant locate Locale/gettext.pm in' $issuedir/title; then
    try_again=1
    add2backlog "$task"
    add2backlog "%perl-cleaner --all"
    return
  fi

  if [[ $try_again -eq 1 ]]; then
    add2backlog "$task"
  else
    echo "=$pkg" >> /etc/portage/package.mask/self
  fi

  IfNewThenSendIssueMail
}


function source_profile(){
  local old_setting=${-//[^u]/}
  set +u
  source /etc/profile 2>/dev/null
  [[ -n "${old_setting}" ]] && set -u || true
}


# helper of PostEmerge()
# switch to latest GCC
function SwitchGCC() {
  local latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)

  if ! gcc-config --list-profiles --nocolor | grep -q -F "$latest *"; then
    local old=$(gcc -dumpversion | cut -f1 -d'.')
    gcc-config --nocolor $latest
    source_profile
    add2backlog "%emerge @preserved-rebuild"
    if grep -q LIBTOOL /etc/portage/make.conf; then
      add2backlog "%emerge -1 sys-devel/slibtool"
    else
      add2backlog "%emerge -1 sys-devel/libtool"
    fi
    add2backlog "%emerge --unmerge sys-devel/gcc:$old"
  fi
}


# helper of RunAndCheck()
# it schedules follow-ups from the last emerge operation
function PostEmerge() {
  # don't change these config files after image setup
  rm -f /etc/._cfg????_{hosts,resolv.conf}
  rm -f /etc/conf.d/._cfg????_hostname
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  # if eg. a new glibc was installed then rebuild the locales
  if ls /etc/._cfg????_locale.gen &>/dev/null; then
    locale-gen > /dev/null
    rm /etc/._cfg????_locale.gen
  elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
    locale-gen > /dev/null
  fi

  # merge the remaining config files automatically
  etc-update --automode -5 1>/dev/null

  # update the environment
  env-update &>/dev/null
  source_profile

  # the very last step after an emerge
  if grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $tasklog_stripped; then
    if [[ $try_again -eq 0 ]]; then
      add2backlog "@preserved-rebuild"
    fi
  fi

  if grep -q  -e "Please, run 'haskell-updater'" \
              -e "ghc-pkg check: 'checking for other broken packages:'" $tasklog_stripped; then
    add2backlog "%haskell-updater"
  fi

  if grep -q  -e ">>> Installing .* dev-lang/perl-[1-9]" \
              -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog "%emerge --depclean"
    add2backlog "%perl-cleaner --all"
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    add2backlog "%SwitchGCC"
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped; then
    local current=$(eselect ruby show | head -n 2 | tail -n 1 | xargs)
    local latest=$(eselect ruby list | tail -n 1 | awk ' { print $2 } ')

    if [[ "$current_time" != "$latest" ]]; then
      add2backlog "%eselect ruby set $latest"
    fi
  fi

  # if 1st prio is empty then check for a schedule of the daily update
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    local last=""
    if [[ -f /var/tmp/tb/@world.history && -f /var/tmp/tb/@system.history ]]; then
      if [[ /var/tmp/tb/@world.history -nt /var/tmp/tb/@system.history ]]; then
        last=/var/tmp/tb/@world.history
      else
        last=/var/tmp/tb/@system.history
      fi
    elif [[ -f /var/tmp/tb/@world.history ]]; then
      last=/var/tmp/tb/@world.history
    elif [[ -f /var/tmp/tb/@system.history ]]; then
      last=/var/tmp/tb/@system.history
    fi

    if [[ -z $last || $(( $(date +%s) - $(stat -c%Y $last) )) -gt 86400 ]]; then
      add2backlog "@world"
      add2backlog "@system"
    fi
  fi
}


# helper of WorkOnTask()
# run ($@) and act on result
function RunAndCheck() {
  (eval $@; rc=$?; echo; date; exit $rc) &>> $tasklog
  local rc=$?

  local taskdirname=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<< $task | tr -c '[:alnum:]' '_')
  tasklog_stripped="/var/tmp/tb/logs/$taskdirname.log"

  filterPlainPext < $tasklog > $tasklog_stripped
  PostEmerge

  if grep -q -F ' -Og -g' /etc/portage/make.conf && [[ -n "$(ls /tmp/core.* 2>/dev/null)" ]]; then
    mkdir -p /var/tmp/tb/core/$taskdirname
    mv /tmp/core.* /var/tmp/tb/core/$taskdirname
    Mail "INFO: keep core files in $taskdirname" "$(ls -lh /var/tmp/tb/core/$taskdirname/)"
  fi

  if [[ $rc -ge 128 ]]; then
    PutDepsIntoWorldFile
    ((signal = rc - 128))
    if [[ $signal -eq 9 ]]; then
      Finish 0 "catched signal $signal - exiting, task=$task"
    else
      Mail "INFO: emerge stopped by signal $signal, task=$task" $tasklog_stripped
    fi

  elif [[ $rc -ne 0 ]]; then
    if grep -q '^>>>' $tasklog_stripped; then
      if DerivePkgFromTaskLog; then
        GotAnIssue
        if [[ $try_again -eq 0 ]]; then
          PutDepsIntoWorldFile
        fi
      else
        Mail "WARN: can't collect data for $task and rc=$rc" $tasklog_stripped
      fi
    elif ! grep -q -f /mnt/tb/data/EMERGE_ISSUES $tasklog_stripped; then
      Mail "unrecognized log for $task" $tasklog_stripped
    fi
  fi

  find /var/log/portage/ -type f -newer $taskfile |\
  while read -r pkglog
  do
    pkglog_stripped=/tmp/$(basename $pkglog)
    filterPlainPext < $pkglog > $pkglog_stripped
    if grep -q -f /mnt/tb/data/CATCH_MISC $pkglog_stripped; then
      pkg=$(cut -f5 -d'/' <<< $pkglog | cut -f1-2 -d':' | tr ':' '/')
      repo=$(portageq metadata / ebuild $pkg repository)

      createAndPrefillIssueDir

      grep -f /mnt/tb/data/CATCH_MISC $pkglog_stripped | tee $issuedir/issue | head -n 1 > $issuedir/title

      mv $pkglog_stripped $issuedir
      phase=""
      finishTitle
      cp $issuedir/issue $issuedir/comment0
      cat << EOF >> $issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

  The output of emerge matches a pattern requested by a Gentoo dev.

EOF
      collectPortageDir
      CreateEmergeHistoryFile
      CompressIssueFiles
      IfNewThenSendIssueMail
    else
      rm $pkglog_stripped
    fi
  done

  return $rc
}


# this is the heart of the tinderbox
function WorkOnTask() {
  try_again=0           # "1" means to retry same task, but with changed/reset USE/ENV/FEATURE/CFLAGS
  unset pkgname pkglog pkglog_stripped
  pkg=""

  # @set
  if [[ $task =~ ^@ ]]; then
    feedPfl

    local opts="--backtrack=30"
    if [[ ! $task = "@preserved-rebuild" ]]; then
      opts="$opts --update"
      if [[ $task = "@system" || $task = "@world" ]]; then
        opts="$opts --changed-use --newuse"
      fi
    fi

    if RunAndCheck "emerge $task $opts"; then
      echo "$(date) ok" >> /var/tmp/tb/$task.history
      if [[ $task = "@world" ]]; then
        add2backlog "%emerge --depclean"
      fi
    else
      echo "$(date) NOT ok $pkg" >> /var/tmp/tb/$task.history
      if [[ -n "$pkg" ]]; then
        if [[ $try_again -eq 0 ]]; then
          if [[ $task = "@preserved-rebuild" ]]; then
            if [[ $(equery d $pkgname | wc -l) -eq 0 ]]; then
              add2backlog "@world"
              add2backlog "@preserved-rebuild"
              add2backlog "%emerge -C $pkgname"
            fi
          else
            add2backlog "%emerge --resume --skip-first"
          fi
        fi
      fi
    fi
    cp $tasklog /var/tmp/tb/$task.last.log

    feedPfl

  # %<command/s>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<< $task)"

    if ! RunAndCheck "$cmd"; then
      if [[ $try_again -eq 0 ]]; then
        if [[ $task =~ " --resume" ]]; then
          if [[ -n "$pkg" ]]; then
            add2backlog "%emerge --resume --skip-first"
          elif grep -q ' Invalid resume list:' $tasklog_stripped; then
            add2backlog "$(tac $taskfile.history | grep -m 1 '^%')"
          fi
        elif [[ ! $task =~ " --unmerge " && ! $task =~ "emerge -C " && ! $task =~ " --depclean" && ! $task =~ " --fetchonly" ]]; then
          Finish 3 "command: '$cmd'"
        fi
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    RunAndCheck "emerge $task" || true

  # a common atom
  else
    RunAndCheck "emerge --update $task" || true
  fi
}


# few repeated @preserved-rebuild are ok
function SquashRebuildLoop() {
  if [[ n=$(tail -n 15 $taskfile.history | grep -c '@preserved-rebuild') -ge 5 ]]; then
    echo -e "#\n#\n#\n#\n#\n" >> $taskfile.history
    echo "@preserved-rebuild" >> /var/tmp/tb/backlog.1st # re-try it asap
    Finish 1 "$FUNCNAME too much @preserved-rebuild" $taskfile.history
  fi
}


function syncRepos()  {
  local diff=${1:-0}

  if emaint sync --auto 1>/dev/null | grep -B 1 '=== Sync completed for gentoo' | grep -q 'Already up to date.'; then
    return
  fi

  # feed backlog.upd with new entries from max 3 hours ago
  local ago
  ((ago = diff + 3600 + 61))
  if [[ $ago -gt 10800 ]]; then
    ago=10800
  fi

  cd /var/db/repos/gentoo
  git diff --diff-filter=ACM --name-status "@{ $ago second ago }".."@{ 60 minute ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' | cut -f2- -s | cut -f1-2 -d'/' -s |
  grep -v -f /mnt/tb/data/IGNORE_PACKAGES |\
  uniq > /tmp/diff.upd

  if [[ -s /tmp/diff.upd ]]; then
    cp /var/tmp/tb/backlog.upd /tmp
    sort -u /tmp/diff.upd /tmp/backlog.upd | shuf > /var/tmp/tb/backlog.upd
    rm /tmp/backlog.upd
  fi
}


#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8
trap Finish INT QUIT TERM EXIT

taskfile=/var/tmp/tb/task           # holds the current task
tasklog=$taskfile.log               # holds output of the current task
name=$(cat /etc/conf.d/hostname)    # the image name
keyword="stable"
if grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf; then
  keyword="unstable"
fi

export CARGO_TERM_COLOR="never"
export GCC_COLORS=""
export OCAML_COLOR="never"
export PY_FORCE_COLOR="0"
export PYTEST_ADDOPTS="--color=no"

# https://bugs.gentoo.org/683118
export TERM=linux
export TERMINFO=/etc/terminfo

export GIT_PAGER="cat"
export PAGER="cat"

echo "/tmp/core.%e.%p.%s.%t" > /proc/sys/kernel/core_pattern

# re-schedule $task
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

last_sync=0  # forces a repo sync
while :
do
  if [[ -f /var/tmp/tb/STOP ]]; then
    echo "#catched STOP file" > $taskfile
    Finish 0 "catched STOP file" /var/tmp/tb/STOP
  fi

  # error-prone
  for i in /mnt/tb/data/IGNORE_ISSUES /mnt/tb/data/IGNORE_PACKAGES
  do
    if grep -q "^$" $i; then
      Finish 1 "empty line(s) in $i"
    fi
  done

  (date; echo) > $tasklog
  current_time=$(date +%s)
  if [[ $(( diff = current_time - last_sync )) -ge 3600 ]]; then
    echo "#sync repos" > $taskfile
    last_sync=$current_time
    syncRepos $diff
  fi
  echo "#get task" > $taskfile
  getNextTask
  WorkOnTask
  echo "#cleanup" > $taskfile
  rm -rf /var/tmp/portage/*
  SquashRebuildLoop
done
