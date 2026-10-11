# Installing Subnautica (locally) on Steam Frame

I wanted to try Subnautica to see how it would work locally on the Steam Frame.
Alas, none of the common mod managers are updated yet so they 'just work'
on such a new device.

So (with the help of my ai buddy) I wrote a little script to fetch and install
bepinex and the Subnautica VR mod (which fixes numerous things in the base subnautica).

## How to install

* Install Subnautica via Steam and run it at least once
* copy [the installer script](../bin/install-subnautica-vr.sh) somewhere onto your steamframe and run it.  It should say success.
* (very important - this lets bepinex install its hooks) In the Steam preferences for Subnautica set the launch command to
```
WINEDLLOVERRIDES="winhttp=n,b" %command%"
```
* Attach a bluetooth game controller - I don't think controller emulation from the vr grips works yet?

IMO performance is good but not amazing.
