---
title: "Monitor hotplugging on Ubuntu"
date: 2023-08-26T13:30:03-06:00
# weight: 1
# aliases: ["/first"]
tags: ["external monitor", "udev", "systemd"]
# author: ["Me", "You"] # multiple authors
showToc: true
TocOpen: false
draft: false
hidemeta: false
comments: false
description: "Showing a cost of following the \"learning by doing\" approach."
#canonicalURL: "https://canonical.url/to/page"
disableHLJS: false # to disable highlightjs
disableShare: false
hideSummary: false
searchHidden: true
ShowReadingTime: true
ShowBreadCrumbs: true
ShowPostNavLinks: true
ShowWordCount: true
ShowRssButtonInSectionTermList: true
UseHugoToc: true
cover:
    image: "<image path/url>" # image path/url
    alt: "<alt text>" # alt text
    caption: "<text>" # display caption under cover
    relative: false # when using page bundles set this to true
    hidden: true # only hide on current single page
editPost:
    URL: "https://github.com/srgpsk/blog/content"
    Text: "Suggest Changes" # edit text
    appendFilePath: true # to append file path to Edit link
---

# Scale system UI on external monitor connection

> \- On scale 1 to 10, how hard we want to make it?  
> \- Yes.

> Please explain why changing those few lines took you so long.  
> -- <cite>Your manager.<cite>

## TL;DR 

[Jump to the solution](#we-dont-quit-we-never-quit-again-again)

## The reason

Ever since I bought a 4K display and started working from home more often, one thing has been bothering me - the need to change the system font size when I connect an external display. This reduces the value of having a 4K monitor, but the convenience to my eyes outweighs the fact that some might think otherwise.
All of the below I applied on Ubuntu 22.04, your system may behave a little differently, or not.

Disclaimer: I'm not, by any mean, an expert in all of this so take this with a grain of salt. 

## The journey

### KISS my hand or Keep It Simple Stupid by hand

The simplest approach the one could use would be create a couple of keyboard shortcuts with:
`gsettings set org.gnome.desktop.interface text-scaling-factor N`
where `N` is a number meaning "scale font Nx times".

That will work, but... I don't know about you, but I, as a piece of biomass, was created to do something meaningful, like spending a few days to deliver this solution and not wasting those precious miliseconds on pressing stupid buttons every time.

### Automate or die

Some theory. To see connected monitors and their resolutions you could utilize `xrandr`, `wlr-randr` or similar tools. I dodn't want to rely on third party, so let's go directly with _drm_:

```bash 
# gives you available resolutions for a specific device
cat /sys/class/drm/card0-HDMI-A-1/modes

# list of resolutions for all HDMI connected devices
cat /sys/class/drm/card*HDMI*/modes

# most general, all devices connected somehow
cat /sys/class/drm/card*/modes
```

The command will give you an unsorted list (contains duplicates) of all resolutions for all connected monitors, including the default one:

```
1600x900
1280x720
3840x2160
3840x2160
3840x2160
2560x1440
```

Unlike the `xrandr` output, here we don't have a mark against current active resolution. In this implementation I'll assume the biggest one across all the monitors is the active one, because as a software developer I know my assumptions are always right 🤪.

#### Shell scripting always makes me ~~cry~~ happy!

Applying that knowledge we could write next script `on-external-display-connection.sh`:

```bash
#!/usr/bin/env bash

MIN_TARGET_X_RESOLUTION=3840 # 4K
TARGET_SCALE_FACTOR=1.5
SCALE_FACTOR=1

### detect if there is any display with >=4K is connected
# shellcheck disable=SC2013
# get all active modes > unique > split and take only horizontal res > sort max to min > get top 1
XRES=$(cat /sys/class/drm/card*/modes | uniq | cut -d 'x' -f 1 | sort -bnr | head -1)
if [ "$XRES" -ge $MIN_TARGET_X_RESOLUTION ]; then
  SCALE_FACTOR=$TARGET_SCALE_FACTOR
fi

### apply defined scale factor system-wide
### capturing real user BUS env var for a reason https://stackoverflow.com/questions/20292578/setting-gsettings-of-other-user-with-sudo
sudo -u 'your_user' DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" gsettings set org.gnome.desktop.interface text-scaling-factor "$SCALE_FACTOR"

logger "$0 system UI font scaling factor was set to $SCALE_FACTOR"
```

And make it executable `chmod u+x on-external-display-connection.sh`.

**Key moments**:
- Pipeline in XRES variable is doing one simple thing: _takes our list -> filters it to have only unique values -> for each value in the list splits it by "x" char and takes only left side of the split -> sorts numerically -> takes the 1st place_. As result we get biggest horizontal resolution across all connected displays. Then we conditionally check if that resolution is big enough to trigger our desire to increase the font.
- gsettings part is already described, ignore sudo and DBUS part for now.

How to run it? Some basic choices come to mind:
- Keyboard shortcut. Again, only if you're a hard worker :-)
- Add it to CRON or systemd, execute every X seconds, once the modes list change - scale factor will be applied.

Well, the first option unworthy of me as a person, the second one is a waste of computer resources.

#### U dev 

Isn't it supposed to be "Ur dev"? I'm so bad with that text messages slang.

Moving forward. Internal feeling suggests that there should be some sort of event that fires on an external display connection. Basic [googling shows](https://bbs.archlinux.org/viewtopic.php?id=170294) that we have `udev` that fires `change` event once we plug in the display.

See it yourself `udevadm monitor -puk` and plug in/out the cable. You'll see 2 events - one from kernel and one from udev ([unless you have Nvidia](https://unix.stackexchange.com/questions/13746/how-can-i-detect-when-a-monitor-is-plugged-in-or-unplugged#comment252057_122301)), we'll focus on the latter one.

```
UDEV  [18128.171280] change   /devices/pci0000:00/0000:00:02.0/drm/card0 (drm)
ACTION=change
DEVPATH=/devices/pci0000:00/0000:00:02.0/drm/card0
SUBSYSTEM=drm
HOTPLUG=1
DEVNAME=/dev/dri/card0
DEVTYPE=drm_minor
SEQNUM=4975
USEC_INITIALIZED=5544009
ID_PATH=pci-0000:00:02.0
ID_PATH_TAG=pci-0000_00_02_0
ID_FOR_SEAT=drm-pci-0000_00_02_0
MAJOR=226
MINOR=0
DEVLINKS=/dev/dri/by-path/pci-0000:00:02.0-card
TAGS= ...
CURRENT_TAGS= ...
```

The important parts of that list are action, subsystem, hotplug and, as you'll see later, seqnum.
Let's write a udev rule `on-external-display-connection.rules` as described (here)[1] and (there)[2]

```
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", RUN+="/path/to/on-external-display-connection.sh"
```

and link it to udev rules dir

`sudo ln -s path/to/on-external-display-connection.rules /etc/udev/rules.d/`

**Key moments**:
- `.rules` extension is important
- We used "==" and "+=" operators in the rule. That line basically tells udev - once conditions (sybsystem, kernel) are met, please run my script.
- Unlike other services udev doesn't work with the user space config, so you have to use privileged user.

Now test. Plug / unplug the cable and it works... kind of. 
In my tests in scaled the font down on plug in and scled up on unplug, which is completely opposite of what I want. 

Why? IDK. Looks like order of execution is _plug in -> event fired -> drm modes updated_, meaning when our script executed the state of modes is not updated yet.
Two potential solutions comes to mind:
- Inverse scale factor values in the script and don't tell anyone, never. Would work if that weird udev behavior would be consitent, but it's not, plus going this way will hunt you down in nightmares.
- Put something like `sleep 3` in the script, basically wait for modes to be updated and then apply our logic. Bat idea also, since udev rule is a bad place for "long" running processes, they will be killed. (I'll find a link that describes it and add it here)

#### Desperate already? No pain, no gain.

Remember you still can [jump to the solution](#we-dont-quit-we-never-quit-again-again)


Moving forward. It's time to introduce a `systemd` service.

What we're going to do is on udev event fired, instead of executing the script directly, we will delegate that part to systemd. I believe if I read all the docs and probably source code I'd understand "why", but learning by doing is my credo (_monkey want type, no think_).
Here's the systemd service file `external-display.service`

```
[Unit]
Description=Scale UI on external display connection

[Service]
Type=simple
User=your_user
ExecStart=/path/to/on-external-display-connection.sh

[Install]
WantedBy=multi-user.target
```

Link it to the corresponding directory:

`sudo ln -s /path/to/external-display.service /etc/systemd/system/` or more conveniently `sytemctl link external-display.service`

And tell udev to run this service instead of our script by updating the rule:

```
ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{HOTPLUG}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="external-display.service"
```

**Key moments**:
- See systemd unit, device, service definition in [additional reads](#additional-reads)
- Now `DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"` part of the [shell script](#shell-scripting-always-makes-me-cry-happy) comes to play. Short description: systemd runs as root, but changes UI settings in user space ... so we tell it to use "user bus" to process that operation. More on that down below.
- The udev rule slightly:
  - Added more explicit conditions, like `ACTION=="change"`, AFAIK udev triggers only "change" event on monitor connection, so the solution should work without this condition, but better to be explicit then to through this again if something changes.
    Env var `HOTPLUG` is another condition for the same reasons  
  -Also as [the docs say][0] systemd expects a rule to be tagged with a `systemd` tag and the service name provided as `SYSTEMD_WANTS` 
Very cool and I like those smart hooks and events, looks very clean and unified. Let's test it.  
Ta-daaam!  
Nothing. Several attempts. Restart deamons, the system itself. Not a thing!  

At this point I feel like this guy

{{< youtube MKn07j6RnYI >}}

Greek gods. I just wanted to make a simple thing, why you're doing this to me.

#### We don't quit. We never quit. Again, again!

Out of desperation I started to read those forums threads more carefully and found [HOTPLUG and SEQNUM][5]

> It seems a new instance of systemd unit file for each and every hotplug is needed. 

Okay, systemd service docs mention [Service Templates][4] but how I suppose to know that hotplu expects new file each time... so frustrating. And I know [I've already seen this approach](https://superuser.com/a/1401322/507470) in SO answers, but chose to ignore it for now, since if that's a workaround around a bug, maybe it's already fixed.  

Following that approach we have:

`150-on-external-display-connection.rules`

```
ACTION=="change", KERNEL=="card0", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{HOTPLUG}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="external-display@$env{SEQNUM}.service"
```

`external-display@.service`   

```
[Unit]
Description=Scale UI on external display connection

[Service]
Type=oneshot
User=your_user
ExecStart=/path/to/on-external-display-connection.sh
```

**Key moments**
- "@" at the end of the name
- `Type=oneshot` instead of "simple", there is slight difference- Lack of [Install] section. At this point we don't really need it, since systemd service will be invoked by udev directly, I think it's called "static" service in their terminology, but I could be mistaked. We likely will need "install" section as you see later.


`on-external-display-connection.sh` is the same 
```
#!/usr/bin/env bash

MIN_TARGET_X_RESOLUTION=3840 # 4K
TARGET_SCALE_FACTOR=1.5
SCALE_FACTOR=1

### detect if there is any display with >=4K is connected
# shellcheck disable=SC2013
# get all active modes > unique > split and take only horizontal res > sort max to min > get top 1
XRES=$(cat /sys/class/drm/card*/modes | uniq | cut -d 'x' -f 1 | sort -bnr | head -1)
if [ "$XRES" -ge $MIN_TARGET_X_RESOLUTION ]; then
  SCALE_FACTOR=$TARGET_SCALE_FACTOR
fi

### apply defined scale factor system-wide
### capturing real user BUS env var for a reason https://stackoverflow.com/questions/20292578/setting-gsettings-of-other-user-with-sudo
sudo -u your_user DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/{{ real_user_id }}/bus" gsettings set org.gnome.desktop.interface text-scaling-factor "$SCALE_FACTOR"

logger "$0 system UI font scaling factor was set to $SCALE_FACTOR"

```

All the files linked to apropriate places as described above.

Test it. Plug / unplug.
I'm gonna cry now, my beautiful baby... it said "daddy" 🤪  
Old gods, such a relief, I was able to kill those disgusting seconds I'd have to spend on doing this manually 😂.

All the code with automated installation can be found [in this repo](https://github.com/srgpsk/laptop/tree/master/external-display)

As a parent you think your child is perfect, but as a software engineer you know you need more test cases.  
So it works now, in runtime, let's keep the cable connected and restart the machine and ... it doesn't work.  
Several attempts, different systemd targets, nope.

TO BE CONTINUED...

### Temporary summary

I really like the idea of hooking up into the system processes in this unified way. I wish tho that the documentation would be more explicit and maybe some examples?  
At this point I devised a plan - I'm going to spend next 10 years on learning C and Linux internals, join the opensource community and fix that SEQNUM behavior. Oh, that sweet revenge.


## Notes to future me:

- Service needs "install" section now. Graphical session target looks like a good point to hook up for this
```
[Install]
WantedBy=graphical-session.target
```
But it doesn't seem like systemd even running the service, syslog is empty. Also check the docs for `[Unit]` Requires= and After=, maybe something is in there.
- Likely it has something to do with how the service runs. Now we're using "system bus with the user privileges", that `User=` in the service. Plus passing "user bus" in the scaling script. Looks messy.
- Try to move everything to user space `systemctl --user ...` etc., unified. `systemctl` has environment load command where we can specify what env vars we need from the user. We may need Xuathority, Dbus and likely Display.
- See targets available for system and real user:
```
# same for devices and services
systemctl --user list-units --type target
systemctl list-units --type target
```
- [Here's](https://unix.stackexchange.com/questions/693485/after-multi-user-target-and-others-not-working-in-a-systemd-service) a good discussion and visuals for targets
- [Here](https://superuser.com/a/1720018/507470) the guy says he mas able to run the service on graphical session target
- Check the grammar, neovim has some lsps for that.

## Additional reads
[0]: https://www.freedesktop.org/software/systemd/man/udev.html
[1]: http://www.reactivated.net/writing_udev_rules.html
[2]: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[3]: https://www.freedesktop.org/software/systemd/man/systemd.device.html
[4]: https://www.freedesktop.org/software/systemd/man/systemd.service.html
[5]: https://bbs.archlinux.org/viewtopic.php?pid=1928268#p1928268
[udev][0]  
[udev rules, blog post][1]  
[systemd.unit][2]  
[systemd.device][3]  
[systemd.service][4]  
[HOTPLUG and SEQNUM][5] 

