function __getStartTime() {
  local b=$(basename $1)

  cat ~tinderbox/img/$b/var/tmp/tb/setup.timestamp
}


function __is_cgrouped() {
  local b=$(basename $1)

  [[ -d /sys/fs/cgroup/cpu/local/$b/ ]]
}


function __is_locked() {
  local b=$(basename $1)

  [[ -d /run/tinderbox/$b.lock/ ]]
}


function __is_running() {
  __is_cgrouped $1 || __is_locked $1
}


# transform the issue of the title into space separated search items and set common vars
function createSearchString() {
  if ! command -v bugz 1>/dev/null; then
    return 2
  fi

  bugz_search=$issuedir/bugz_search
  bugz_result=$issuedir/bugz_result

  for f in $bugz_search $bugz_result
  do
    if [[ ! -f $f ]]; then
      truncate -s 0 $f
      chmod a+rw    $f
    fi
  done

  sed -e 's,^.* - ,,'     \
      -e 's,/\.\.\./, ,'  \
      -e 's,[\(\)], ,g'   \
      -e 's,\s\s*, ,g'    \
      $issuedir/title > $bugz_search
}


function GotResults() {
  if [[ -s $bugz_result ]]; then
    if ! grep -q "^Traceback" $bugz_result; then
      return 0
    fi
  fi
  return 1
}


function SearchForSameIssue() {
  if grep -q 'file collision with' $issuedir/title; then
    # for a file collision report both involved sites
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    bugz -q --columns 400 search --show-status -- "file collision $pkgname $collision_partner_pkgname" |\
        grep -e " CONFIRMED " -e " IN_PROGRESS " |\
        sort -u -n -r |\
        head -n 4 |\
        tee $bugz_result
    if GotResults; then
      return 0
    fi
  fi

  for i in $pkg $pkgname
  do
    bugz -q --columns 400 search --show-status -- $i "$(cat $bugz_search)" |\
        grep -e " CONFIRMED " -e " IN_PROGRESS " |\
        sort -u -n -r |\
        head -n 4 |\
        tee $bugz_result
    if GotResults; then
      return 0
    fi
  done

  return 1
}


function SearchForSimilarIssue() {
  # resolved does not fit "same issue"
  for i in $pkg $pkgname
  do
    bugz -q --columns 400 search --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(cat $bugz_search)" |\
        sort -u -n -r |\
        head -n 3 |\
        tee $bugz_result
    if GotResults; then
      echo -e " \n^^ DUPLICATE\n"
      return 0
    fi

    bugz -q --columns 400 search --show-status --status RESOLVED -- $i "$(cat $bugz_search)" |\
        sort -u -n -r |\
        head -n 3 |\
        tee $bugz_result
    if GotResults; then
      return 0
    fi
  done

  # now search without version/revision

  local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
  local g='stabilize|Bump| keyword| bump'

  echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
  bugz -q --columns 400 search --show-status $pkgname |\
      grep -v -i -E "$g" |\
      sort -u -n -r |\
      head -n 12 |\
      tee $bugz_result
  if GotResults; then
    return 0
  fi

  if [[ $(wc -l < $bugz_result) -lt 5 ]]; then
    echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
    bugz -q --columns 400 search --status RESOLVED $pkgname |\
        grep -v -i -E "$g" |\
        sort -u -n -r |\
        head -n 5 |\
        tee $bugz_result
    if GotResults; then
      return 0
    fi
  fi

  return 1
}
