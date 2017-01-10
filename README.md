# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## installation
Create the user *tinderbox*

    useradd -m tinderbox
and run its home directory */home/tinderbox*
    
    mkdir ~/images ~/logs ~/run ~/tb
Unpack *./bin*, *./data* and *./sdata* into *~/tb*.
Edit the files in *~/sdata* and strip away the suffix *.sample*.
Grant to the user these sudo rights:
    
    tinderbox ALL=(ALL) NOPASSWD: /home/tinderbox/tb/bin/chr.sh,/home/tinderbox/tb/bin/tbs.sh,/usr/bin/chroot
Create one or more big directories to hold the chroot images.

## usage
###setup of a new image
The setup of a new image is made by *tbs.sh*.
    
    cd ~/images; sudo ~/tb/bin/tbs.sh 
A profile, keyword and a USE flag set are choosen.
The current stage3 file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled.
Few required packages (*ssmtp*, *pybugz* etc.) are installed.
The package list */tmp/packages* is created from all visible packages.
The upgrade of GCC and the switch to libressl - if applicable - are scheduled as the first tasks.
A symlink is made into *~/run*.

###start of an image
    
    ~/tb/bin/start_img.sh <image name>

The wrapper *runme.sh* calls the tinderbox script *job.sh* itself.
It basically parses the output of *cat /tmp/packages | xargs -n 1 emerge -u*.
It uses *chr.sh* to handle the chroot related actions.

###stop of an image
    
    ~/tb/bin/stop_img.sh <image name>

A marker (*/tmp/STOP*) is made in that image.
The current emerge operation will be finished before *job.sh* exits.

###removal of an image
Just remove the symlink in *~/run*.
The chroot image itself might be kept around as long as it is needed.

###reported findings
All findings are reported email to the user specified in the variable *mailto*.
Bugs can be filed using *bgo.sh*.

## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

