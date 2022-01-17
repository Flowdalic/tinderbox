#!/bin/bash
# set -x


# call this eg by:
# grep 'setup phase' ~/tb/data/ALREADY_CATCHED | sed -e 's,\[.*\] ,,g' | cut -f1 -d' ' -s | xargs -r qatom -F "%{CATEGORY}/%{PN}" | xargs retest.sh


set -eu
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/$(basename $0).txt  # package/s for the appropriate backlog
truncate -s 0 $result

grep    -e '^@' -e '^%' -e '^='        <<< ${@} >> $result || true
grep -v -e '^@' -e '^%' -e '^=' -e '#' <<< ${@} |\
xargs --no-run-if-empty -n 1 |\
sort -u |\
while read -r atom
do
  echo "$atom" >> $result
  # delete from global and image specific files
  pkgname=$(qatom -F "%{CATEGORY}/%{PN}" "$atom" 2>/dev/null | grep -v -F '<unset>' | sed -e 's,/,\\/,g')
  if [[ -n "$pkgname" ]]; then
    if ! sed -i -e "/$pkgname/d" \
        ~tinderbox/tb/data/ALREADY_CATCHED \
        ~tinderbox/run/*/etc/portage/package.mask/self \
        ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null; then
      # ^^ those files might not exist currently
      :
    fi
  fi
done

if [[ -s $result ]]; then
  for i in $(ls ~tinderbox/run 2>/dev/null)
  do
    bl=~tinderbox/run/$i/var/tmp/tb/backlog.1st
    # filter out dups, then put new entries after existing ones
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    mv $bl.tmp $bl
  done
fi
