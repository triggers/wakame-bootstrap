
# Quick Start

First, create a minimal installation of CentOS 6.5 and log in as root.
Copy the `wakame-vdc-install-hierarchy.sh` script to any directory.
Then a typical install of Wakame-vdc can be done with this sequence of
commands.

     $ time bash ./wakame-vdc-install-hierarchy.sh do
     $ /tmp/setup-bridge.sh
     $ time bash ./wakame-vdc-install-hierarchy.sh do
     $ time bash ./wakame-vdc-install-hierarchy.sh do

The first time, the script will catch that no bridge device has been
set up, so it will create a custom script to create the bridge.
The second line runs that script.

The third line should do the whole install and start Wakame-vdc.  However,
for some (probably very simple) reason, vdc-webui does not start.  Running
the script a 4th time catches this.

# Do not just read the script!

First do this:

     $ time bash ./wakame-vdc-install-hierarchy.sh check

And get a feel for how it is split up into separate steps and what the
dependencies are between the steps.  Pick a step of interest and use
search in your editor to find that second of the code, which by itself
should be short and easy to read.


