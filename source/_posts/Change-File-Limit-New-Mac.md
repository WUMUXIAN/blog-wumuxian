---
title: Change Open File Limit on MacOS
date: 2016-05-24 10:18:22
tags: MacOS, Open File Limit
category: Infrastructure
---

OSX has a very low limit on the maximum number of open files. It causes problem now and then if you're doing development and use load testing tools. To address the problem you can change the open file limit by doing the following:

# MacOS <= 10.7 (Lion)
```bash
sudo launchctl limit maxfiles 1000000 1000000
echo "limit maxfiles 1000000 1000000" | sudo tee -a /etc/launchd.conf
```
Now you will have the the maxfiles limit updated after next reboot, you can use ulimit to adjust the limit for the current session:
```
ulimit -n 65335 65335
```

# MacOS = 10.8 (Mountain Lion)
```bash
echo kern.maxfiles=65536 | sudo tee -a /etc/sysctl.conf
echo kern.maxfilesperproc=65536 | sudo tee -a /etc/sysctl.conf
sudo sysctl -w kern.maxfiles=65536
sudo sysctl -w kern.maxfilesperproc=65536
```
Now you will have the maxfiles limit updated after next reboot, you can can use ulimit to adjust the limit for the current session:
```
ulimit -n 65336 65336
```

# MacOS >= 10.9 (Mavericks, Yosemite and E1 Capitan)
Create a file at /Library/LaunchDaemons/limit.maxfiles.plist
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>limit.maxfiles</string>
    <key>ProgramArguments</key>
    <array>
      <string>launchctl</string>
      <string>limit</string>
      <string>maxfiles</string>
      <string>524288</string>
      <string>524288</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ServiceIPC</key>
    <false/>
  </dict>
</plist>
```
Now you will have the maxfiles limit updated after next reboot, you can can use ulimit to adjust the limit for the current session:
```
ulimit -n 65335 65335
```
