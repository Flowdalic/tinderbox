#!/bin/bash
# set -x

# crontab example:
# * * * * * /opt/tb/bin/logcheck.sh

set -eu
export LANG=C.utf8

f=/tmp/$(basename $0).out

if [[ ! -s $f ]]; then
  if [[ $(wc -c < <(cat ~/logs/*.log 2>/dev/null)) != 0 ]]; then
    (
      ls -l ~/logs/
      echo
      head -v ~/logs/*.log | tee $f
      echo
      echo -e "\n\nto re-activate this test again, do:\n\n  tail -v ~/logs/*; rm -f $f;     truncate -s 0 ~/logs/*\n\n"
    ) | mail -s "INFO: tinderbox logs" ${MAILTO:-tinderbox}
  fi
fi
