#!/bin/bash
# set -x


set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

result=/tmp/${0##*/}.txt  # package/s for the appropriate backlog
truncate -s 0 $result

grep -e '@' -e '%' -e '=' <<< ${@} >> $result || true

grep -v -e '@' -e '%' -e '=' <<< ${@} |\
xargs -n 1 |\
sort -u |\
while read -r atom
do
  echo "$atom" >> $result

  # delete a package in global and image specific files
  pkgname=$(qatom -F "%{CATEGORY}/%{PN}" "$atom" 2>/dev/null | grep -v -F '<unset>')
  if [[ -n "$pkgname" ]]; then
    if ! sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)/d"  \
        ~/tb/data/ALREADY_CATCHED                     \
        ~/run/*/etc/portage/package.mask/self         \
        ~/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null; then
      # ^^ not all files might exist in current ~/run
      :
    fi
  fi
done

if [[ -s $result ]]; then
  for i in $(__list_images)
  do
    bl=$i/var/tmp/tb/backlog.1st
    # filter out dups, then put new entries after existing ones
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    mv $bl.tmp $bl

    # force a repo sync before re-test
    sed -i -e '/%syncRepos/d' $bl
    echo "%syncRepos" >> $bl
  done
fi
