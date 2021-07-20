#!/bin/bash
# set -x

# create ~tinderbox/img/index.html from .reported file in issues directory



function listImages()  {
  cat << EOF >> $tmpfile

<br>
<h2>content of image directory</h2>

<i>image</i>/var/tmp/tb contains ./logs and ./issues

EOF
  ls  ~tinderbox/img/ |\
  while read d
  do
    cat << EOF >> $tmpfile
  <a href="./$d">$d</a><br>
EOF
  done

  cat << EOF >> $tmpfile

EOF
}


function listBugs() {
  cat << EOF >> $tmpfile
<h2>reported <a href="https://bugs.gentoo.org/">Gentoo Bugs</a></h2>

<table border="0" align="left" class="list_table">

  <thead align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>/etc/portage/</th>
      <th>IssueDir</th>
    </tr>
  </thead>

  <tfoot align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>/etc/portage</th>
      <th>Issue</th>
    </tr>
  </tfoot>

  <tbody>

EOF

  ls -t ~tinderbox/img/*/var/tmp/tb/issues/*/.reported |\
  while read -r f
  do
    buguri=$(cat $f)
    bugno=$(cut -f2 -d'=' <<< $buguri)
    d=${f%/*}
    ftitle=$d/title
    image=$(cut -f5 -d'/' <<< $d)
    cat << EOF >> $tmpfile
    <tr>
      <td><a href="$buguri">$bugno</a></td>
      <td>$(recode ascii..html < $ftitle)</td>
      <td><a href="./$image/">$image</a></td>
      <td><a href="./$image/etc/portage/">link</a></td>
      <td><a href="$(cut -f5- -d'/' <<< $d)/">link</a></td>
    </tr>
EOF

  done

  cat << EOF >> $tmpfile
  </tbody>
</table>

EOF
}


function DisallowRobots() {
  cat << EOF > ~tinderbox/img/robots.txt
User-agent: *
Disallow: /

EOF
}


#######################################################################
set -eu
export LANG=C.utf8

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

cat << EOF >> $tmpfile
<html>

<h1>recent <a href="https://zwiebeltoralf.de/tinderbox.html">tinderbox</a> data</h1>

EOF

listBugs
listImages

cat << EOF >> $tmpfile
</html>

EOF

if ! diff -q $tmpfile ~tinderbox/img/index.html 1>/dev/null; then
  cp $tmpfile ~tinderbox/img/index.html
  DisallowRobots
fi

rm $tmpfile
