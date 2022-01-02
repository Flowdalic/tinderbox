#!/bin/bash
# set -x

# print tinderbox statistics


function PrintImageName()  {
  printf "%-${2}s" $(cut -c-$2 < $1/var/tmp/tb/name)
}


function check_history()  {
  local file=$1
  local flag=$2

  # eg.:
  # X = @x failed even to start
  # x = @x failed due to a package
  # . = never run before
  #   = no issues
  # ? = internal error
  if [[ -s $file ]]; then
    local line=$(tail -n 1 $file)
    if grep -q " NOT ok " <<< $line; then
      if grep -q " NOT ok $" <<< $line; then
        local uflag=$(tr '[:lower:]' '[:upper:]' <<< $flag)
        flags+="${uflag}"
      else
        flags+="${flag}"
      fi
    elif grep -q " ok$" <<< $line; then
      flags+=" "
    else
      flags+="?"
    fi
  else
    flags+="."
  fi
}


# whatsup.sh -o
#
# compl fail new day backlog .upd .1st swprs 7#7 running
#  4402   36   1 4.8   16529    7    0  W r  ~/run/17.1-20210306-163653
#  4042   26   0 5.1   17774   12    2    r  ~/run/17.1_desktop_gnome-20210306-091529
function Overall() {
  local running=$(ls /run/tinderbox/ 2>/dev/null | grep -c '\.lock$' || true)
  local all=$(wc -w <<< $images)
  echo "compl fail new  day backlog .upd .1st wp rs $running#$all running"

  for i in $images
  do
    local days=$(echo "scale=1; ( $(date +%s) - $(getStartTime $i) ) / 86400.0" | bc)
    local bgo=$(set +f; ls $i/var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l)

    local compl=0
    f=$i/var/log/emerge.log
    if [[ -f $f ]]; then
      compl=$(grep -c ' ::: completed emerge' $f) || true
    fi

    # count emerge failures based on distinct package name+version+release
    # example of an issue directory name: 20200313-044024-net-analyzer_iptraf-ng-1.1.4-r3
    local fail=0
    if [[ -d $i/var/tmp/tb/issues ]]; then
      fail=$(ls -1 $i/var/tmp/tb/issues | while read -r i; do echo $(basename $i); done | cut -f3- -d'-' -s | sort -u | wc -w)
    fi

    local bl=$( wc -l 2>/dev/null < $i/var/tmp/tb/backlog     || echo 0)
    local bl1=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.1st || echo 0)
    local blu=$(wc -l 2>/dev/null < $i/var/tmp/tb/backlog.upd || echo 0)

    # "r" image is running
    # " " image is NOT running
    local flags=""

    # result of last run of @world and @preserved-rebuild respectively:
    #
    # upper case: an error occurred
    # lower case: just a package failed
    # "." not yet run
    # " " ok
    check_history $i/var/tmp/tb/@world.history              w
    check_history $i/var/tmp/tb/@preserved-rebuild.history  p
    flags+=" "
    if __is_running $i ; then
      flags+="r"
    else
      flags+=" "
    fi
    # "S" STOP file
    # "s" STOP in backlog.1st
    if [[ -f $i/var/tmp/tb/STOP ]]; then
      flags+="S"
    elif grep -q "^STOP" $i/var/tmp/tb/backlog.1st 2>/dev/null; then
      flags+="s"
    else
      flags+=" "
    fi

    # images during setup are not yet symlinked to ~tinderbox/run
    local b=$(basename $i)
    [[ -e ~tinderbox/run/$b ]] && d="~/run" || d="~/img"  # shorten output
    printf "%5i %4i %3i %4.1f %7i %4i %4i %5s %s/%s\n" $compl $fail $bgo $days $bl $blu $bl1 "$flags" "$d" "$b" 2>/dev/null
  done
}


# whatsup.sh -t
# 17.1_desktop-20210102  0:19 m  dev-ros/message_to_tf
# 17.1_desktop_plasma_s  0:36 m  dev-perl/Module-Install
function Tasks()  {
  ts=$(date +%s)
  for i in $images
  do
    PrintImageName $i 30
    if ! __is_running $i ; then
      echo
      continue
    fi

    tsk=$i/var/tmp/tb/task
    if [[ ! -s $tsk ]]; then
      echo
      continue
    fi
    task=$(cat $tsk)

    set +e
    let "delta = $ts - $(stat -c %Y $tsk)"
    let "minutes = $delta / 60 % 60"
    if [[ $delta -lt 3600 ]]; then
      let "seconds = $delta % 60 % 60"
      printf "%3i:%02i m " $minutes $seconds
    else
      let "hours = $delta / 60 / 60"
      printf "%3i:%02i h " $hours $minutes
    fi
    set -e

    if [[ ! $task =~ "@" && ! $task =~ "%" && ! $task =~ "#" ]]; then
      echo -n " "
    fi
    echo $task | cut -c1-$((columns-38))
  done
}


# whatsup.sh -l
#
# 17.1_desktop_plasma_s  0:02 m  >>> AUTOCLEAN: media-sound/toolame:0
# 17.1_systemd-20210123  0:44 m  >>> (1 of 2) sci-libs/fcl-0.5.0
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName $i 30
    if ! __is_running $i ; then
      echo
      continue
    fi

    # display the last *started* emerge operation
    tac $i/var/log/emerge.log 2>/dev/null |\
    grep -m 1 -e ' >>> ' -e ' *** emerge' -e ' *** terminating.' -e ' ::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /$,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* .*/ /g' |\
    perl -wane '
      chop ($F[0]);
      my $delta = time() - $F[0];
      $minutes = $delta / 60 % 60;
      if ($delta < 3600) {
        $seconds = $delta % 60 % 60;
        printf ("%3i:%02i m  ", $minutes, $seconds);
      } else  {
        $hours = $delta / 60 / 60;
        printf ("%3i:%02i h%s ", $hours, $minutes, $delta < 7200 ? " " : "!");    # mark long runtimes
      }
      my $line = join (" ", @F[1..$#F]);
      print substr ($line, 0, '"'$((columns-38))'"');
    '
    echo
  done
}


# whatsup.sh -d
#                                                         1d   2d   3d   4d   5d   6d   7d   8d   9d  10d
# 17.1_no_multilib-j3_debug-20210620-175917            1704 1780 1236 1049 1049  727  454  789
# 17.1_desktop_systemd-j3_debug-20210620-181008        1537 1471 1091  920 1033  917  811  701´
function PackagesPerImagePerRunDay() {
  printf "%54s" ""
  max=$(( (columns-54)/5-1 ))
  for i in $(seq 0 $max); do printf "%4id" $i; done
  echo

  for i in $(ls -d ~tinderbox/run/* 2>/dev/null | sort -t '-' -k 3,4)
  do
    PrintImageName $i 54

    local start_time=$(getStartTime $i)
    perl -F: -wane '
      BEGIN {
        @packages   = ();  # helds the amount of emerge operations per runday
      }

      my $epoch_time = $F[0];
      next unless (m/::: completed emerge/);

      my $rundays = int( ($epoch_time - '$start_time') / 86400);
      $packages[$rundays]++;

      END {
        if ($#packages >= 0) {
          $packages[$rundays] += 0;
          foreach my $rundays (0..$#packages) {
            ($packages[$rundays]) ? printf "%5i", $packages[$rundays] : printf "    -";
          }
        }
        print "\n";
      }
    ' $i/var/log/emerge.log 2>/dev/null
  done
}


function getCoveredPackages() {
  grep -H '::: completed emerge' ~tinderbox/$1/*/var/log/emerge.log |\
  # handle ::local
  tr -d ':' |\
  awk ' { print $7 } ' |\
  xargs --no-run-if-empty qatom -F "%{CATEGORY}/%{PN}" |\
  sort -u
}


#  whatsup.sh -c
# 19280 packages in ::gentoo
# 15836 packages in ~tinderbox/run   (82% for last  9 days)
# 17749 packages in ~tinderbox/img   (92% for last 48 days)
function Coverage() {
  local all=$(mktemp  /tmp/$(basename $0)_XXXXXX.all)
  (cd /var/db/repos/gentoo; ls -d *-*/*; ls -d virtual/*) | grep -v -F 'metadata.xml' | sort > $all
  local N=$(wc -l < $all)
  printf "%5i packages in ::gentoo\n" $N

  for i in run img
  do
    local covered=~tinderbox/img/packages.$i.covered.txt
    local uncovered=~tinderbox/img/packages.$i.uncovered.txt

    getCoveredPackages $i > $covered
    diff $covered $all | grep -F '>' | cut -f2 -d' ' -s > $uncovered

    local n=$(wc -l < $covered)
    local oldest=$(cat ~tinderbox/$i/17*/var/tmp/tb/setup.timestamp 2>/dev/null | sort -u -n | head -n 1)
    local days=$(( ( $(date +%s) - $oldest ) / 3600 / 24 ))
    local perc=$((100 * $n / $N))
    printf "%5i packages in ~tinderbox/%s   (%2i%% for last %2i days)" $n $i $perc $days
    echo
  done

  rm $all
}


# whatsup.sh -p
#
# package revisions x emerge times
# 3006x1 824x2 387x3 197x4 171x5 137x6 154x7 136x8 84x9 79x10 109x11 286x12 6x13 6x14 6x15
function CountEmergesPerPackages()  {
  echo "package revisions x emerge times"

  perl -wane '
    BEGIN {
      my %pet = ();     # package => emerge times
    }

    next unless (m/::: completed emerge/);

    my $pkg = $F[7];
    $pet{$pkg}++;

    END {
      my %h = ();       # pet => occurrence

      for my $key (sort keys %pet)  {
        my $value = $pet{$key};
        $h{$value}++;
      }

      my $total = 0;    # total amount of emerge operations
      my $seen = 0;     #              of packages
      my $max = 0;      # max times of being emerged

      for my $key (sort { $a <=> $b } keys %h)  {
        my $value = $h{$key};
        $seen += $value;
        $total += $key * $value;
        print " ", $value, "x", $key;
        $max = $key if ($max < $key);
      }

      for my $key (sort keys %pet)  {
        print " ", $key if ($max == $pet{$key});
      }
      print "\n\n $seen package revisions in $total emerges\n";
    }
  ' ~tinderbox/run/*/var/log/emerge.log
}


# whatsup.sh -e
# yyyy-mm-dd   sum   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23
#
# 2021-04-31    15   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0  15   0   0   0
# 2021-05-01  2790  28  87  91  41   4  13   0   1  15  29  78  35  62  46  75   9   0 193 104 234 490 508 459 188
function emergeThruput()  {
  echo -n "yyyy-mm-dd   sum  "
  for i in {0..23}
  do
    printf "  %2i" $i
  done
  echo -e "\n"

  perl -F: -wane '
    BEGIN {
      my %Day = ();
    }
    {
      next unless (m/::: completed emerge/);

      my $epoch_time = $F[0];
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time);
      $year += 1900;
      $mon += 1;
      $mon = "0" . $mon if ($mon < 10);
      $mday = "0" . $mday if ($mday < 10);

      my $key = $year . "-" . $mon . "-" . $mday;
      $Day{$key}->{$hour}++;
      $Day{$key}->{"sum"}++;
    }

    END {
      for my $key (sort { $a cmp $b } keys %Day)  {
        printf("%s %5i  ", $key, $Day{$key}->{"sum"});
        foreach my $hour(0..23) {
          printf("%4i", $Day{$key}->{$hour} ? $Day{$key}->{$hour} : 0);
        }
        print "\n";
      }
    }
  ' $(find ~tinderbox/img/*/var/log/emerge.log -mtime -14 | sort -t '-' -k 3,4) |\
  tail -n 14
}


#############################################################################
#
# main
#
set -eu
export LANG=C.utf8
unset LC_TIME

source $(dirname $0)/lib.sh

images=$(__list_images)

if ! columns=$(tput cols 2>/dev/null); then
  columns=100
fi

while getopts cdelopt opt
do
  case $opt in
    c)  Coverage                  ;;
    d)  PackagesPerImagePerRunDay ;;
    e)  emergeThruput             ;;
    l)  LastEmergeOperation       ;;
    o)  Overall                   ;;
    p)  CountEmergesPerPackages   ;;
    t)  Tasks                     ;;
  esac
  echo
done
