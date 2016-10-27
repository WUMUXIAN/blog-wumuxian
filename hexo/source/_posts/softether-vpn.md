---
title: How to Set up SoftEther VPN Server and Client for AWS VPC Environment
date: 2016-10-26 14:21:55
tags:
  - VPN
  - Security
category:
  - Infrastructure
---

This article introduces how to set up a SoftEther VPN server on AWS EC2 instance that resides in a public subnet of a AWS VPC and how to set up VPN client on Mac OS to make VPN connection, which enables the client to access the private instances located within the private subnets of the same VPC using their private IP as if they're in the same local network.

![AWS VPC with VPN connection](vpc_vpn.png)

## Why Use SoftEther VPN

SoftEther VPN is one of the most powerful and easit VPN software. It's free and open sources, developed in University of Tsukuba, Japan. 

As an alternative to OpenVPN, SoftEther exceeds OpenVPN in various aspects:

1. Supports more VPN protocols than just OpenVPN only, e.g. L2TP/IPSec, L2TPv3/IPsec, EtherIP, and etc.
2. Newer and more active development. OpenVPN has been stalled for many years and no improvement is introduced for the recent years. However SoftEther is released in 2013 and is under active development.
3. SoftEther has built-in VPN clients on most of the common used OS while OpenVPN doesn't have.
4. SoftEther is faster, >900Mbps throughput compared to OpenVPN <100Mbps.
5. Offers Dynamic DNS and NAT Traversal while OpenVPN doesn't
5. Offers GUI Management while OpenVPN doesn't.
6. Offers a user management system while OpenVPN doesn't.

## Install SoftEther Server

SSH to your AWS EC2 instance and make sure the following software are installed and enabled:

* gcc software
* binutils software
* tar, gzip or other software for extracting package files
* chkconfig system utility
* cat, cp or other basic file operation utility
* EUC-JP, UTF-8 or other code pagccge table for use in a Japanese language environment
* libc (glibc) library
* zlib library
* openssl library
* readline library
* ncurses library
* pthread library

If you're using a AWS Linux AMI, you should have most of them, the only thing you need to install is gcc. 

```bash
sudo yum install gcc -y
```

Now download the linux distribution of SoftEther Server at the [download link](http://www.softether-download.com/en.aspx?product=softether]) by selection the right component and platform:

![Download Page](download.jpeg)

Copy the URL address, download it and extract it:

```bash
wget -O softether-vpnserver.tar.gz http://www.softether-download.com/files/softether/v4.20-9608-rtm-2016.04.17-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.20-9608-rtm-2016.04.17-linux-x64-64bit.tar.gz
tar -zxvf softether-vpnserver.tar.gz
```

If all the dependencies mentioned above are installed and enabled, you should now be able to make the project:

```bash
cd vpnserver
make
```

You will be prompted a set of questions, Choose '1' (yes) all the way to the end and you will get the vpnserver executable when the make command is completed successfully.

```bash
...

Did you read and understand the License Agreement ?
(If you couldn't read above text, Please read 'ReadMeFirst_License.txt'
 file with any text editor.)

 1. Yes
 2. No

Please choose one of above number:
1

...
```

Now move the location of the whole forder to the /usr/local/ directory:

```bash
cd ..
sudo mv vpnserver /usr/local
sudo chmod -R root:root /usr/local/vpnserver
ls -la /usr/local/vpnserver/
total 10504
drwxrwxr-x  9 root root    4096 Oct 27 07:10 .
drwxr-xr-x 13 root root    4096 Oct 26 07:14 ..
-rw-------  1 root root       0 Oct 27 05:55 .VPN-49BDCFFA14
-rw-------  1 root root      11 Oct 27 05:55 .ctl_6BE712FB1B726B608526E5B2444A260A
-rwxrwxr-x  1 root root    1533 Apr 17  2016 .install.sh
-rw-------  1 root root       5 Oct 27 05:55 .pid_6BE712FB1B726B608526E5B2444A260A
-rwxrwxr-x  1 root root    1881 Apr 17  2016 Authors.txt
-rwxrwxr-x  1 root root    2138 Apr 17  2016 Makefile
-rwxrwxr-x  1 root root   30801 Apr 17  2016 ReadMeFirst_Important_Notices_cn.txt
-rwxrwxr-x  1 root root   36297 Apr 17  2016 ReadMeFirst_Important_Notices_en.txt
-rwxrwxr-x  1 root root   50695 Apr 17  2016 ReadMeFirst_Important_Notices_ja.txt
-rwxrwxr-x  1 root root   58932 Apr 17  2016 ReadMeFirst_License.txt
drwx------  2 root root    4096 Oct 27 07:00 backup.vpn_server.config
drwx------  2 root root    4096 Oct 26 06:57 chain_certs
drwxrwxr-x  2 root root    4096 Oct 26 06:57 code
-rwxrwxr-x  1 root root 1295106 Apr 17  2016 hamcore.se2
-rw-------  1 root root     867 Oct 26 06:57 lang.config
drwxrwxr-x  2 root root    4096 Oct 26 06:57 lib
drwx------  3 root root    4096 Oct 26 08:10 packet_log
drwx------  4 root root    4096 Oct 26 07:42 security_log
drwx------  2 root root    4096 Oct 27 01:06 server_log
-rw-r--r--  1 root root      15 Oct 26 10:10 vi
-rw-------  1 root root   14289 Oct 27 07:10 vpn_server.config
-rwxrwxr-x  1 root root 4593563 Oct 26 06:57 vpncmd
-rwxrwxr-x  1 root root 4593703 Oct 26 06:57 vpnserver
```
Finally, perform a check using the *vpncmd* command line to see whether SoftEther VPN server can operate peroperly on your system:

```bash
cd /usr/local/vpnserver
./vpncmd
vpncmd command - SoftEther VPN Command Line Management Utility
SoftEther VPN Command Line Management Utility (vpncmd command)
Version 4.20 Build 9608   (English)
Compiled 2016/04/17 21:59:35 by yagi at pc30
Copyright (c) SoftEther VPN Project. All Rights Reserved.

By using vpncmd program, the following can be achieved.

1. Management of VPN Server or VPN Bridge
2. Management of VPN Client
3. Use of VPN Tools (certificate creation and Network Traffic Speed Test Tool)

Select 1, 2 or 3: 3

VPN Tools has been launched. By inputting HELP, you can view a list of the commands that can be used.

VPN Tools>check
Check command - Check whether SoftEther VPN Operation is Possible
---------------------------------------------------
SoftEther VPN Operation Environment Check Tool

Copyright (c) SoftEther VPN Project.
All Rights Reserved.

If this operation environment check tool is run on a system and that system passes, it is most likely that SoftEther VPN software can operate on that system. This check may take a while. Please wait...

Checking 'Kernel System'...
              Pass
Checking 'Memory Operation System'...
              Pass
Checking 'ANSI / Unicode string processing system'...
              Pass
Checking 'File system'...
              Pass
Checking 'Thread processing system'...
              Pass
Checking 'Network system'...
              Pass

All checks passed. It is most likely that SoftEther VPN Server / Bridge can operate normally on this system.

The command completed successfully.

VPN Tools>exit
```

If you see everything passed successfully, your system is good and VPN server can safely be used.

## Configure the OS

After installing it, in order to make SoftEther VPN server to work properly, we need to configure the OS environment. There are essentially 4 things that we need to do to get it working:

#### Enable IP forward
```bash
sudo sysctl -w net.ipv4.ip_forward = 1
```

#### Add a POSTROUTING rule to NAT table and make it persistent
```bash
iptables -t nat -A POSTROUTING -s 192.168.7.1/24 -j SNAT --to-source 10.10.0.41

# Check whether it's added
iptables -t nat -L
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination

Chain INPUT (policy ACCEPT)
target     prot opt source               destination

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination

Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination
SNAT       all  --  ip-192-168-7-0.ec2.internal/24  anywhere             to:10.10.0.41

# Make it persistent
sudo service iptables save
iptables: Saving firewall rules to /etc/sysconfig/iptables:[  OK  ]

# Double check again
sudo service iptables status
Table: nat
Chain PREROUTING (policy ACCEPT)
num  target     prot opt source               destination

Chain INPUT (policy ACCEPT)
num  target     prot opt source               destination

Chain OUTPUT (policy ACCEPT)
num  target     prot opt source               destination

Chain POSTROUTING (policy ACCEPT)
num  target     prot opt source               destination
1    SNAT       all  --  192.168.7.0/24       0.0.0.0/0            to:10.10.0.41
```
Note that the IP 192.168.7.1 is the VPN Server IP for it's local bridge setup, which we will introduce later, and the IP 10.10.0.41 is the private IP of the VPN Server.

#### Start a DHCP Server with static routing configured
```bash
sudo yum install dnsmasq -y
vi /etc/dnsmasq.conf

interface=tap_vpn
dhcp-range=tap_vpn,192.168.7.10,192.168.7.100,12h
dhcp-option=tap_vpn,3,192.168.7.1
dhcp-option=tap_vpn,249,10.10.0.0/16,192.168.7.1

sudo service dnsmasq start
sudo chkconfig dnsmasq on
```

In the above setup, we created a DHCP server for the network interface tap "vpn", the DHCP IP range is between 192.168.7.10 to 192.168.7.100, the router is set at 192.168.7.1 and the static routing routes all traffic from the router 192.168.7.1 to 10.10.0.0/16, which is the VPC CIDR in my case. The tap_vpn inferface is going to be used by the SoftEther VPN server to setup the local bridge.

#### Disable Source/Destination Check for the instance

Go to your AWS console and disable the source/dest check for your VPN instance.

![Disable Source/Destination Check](sourcedest.jpeg)

The reason why we setup the DHCP server is that we're not gonna use the SecureNAT option provided by SoftEther, we will use Local Bridge instead because it's less CPU consuming and it's faster in terms of speed. And Local Bridge requires a DHCP server to be up and running. The IP addresses mentioned above can be changed to reflect your actual settings, you don't have to follow exactly the same setup. 
 
## Setup SoftEther Server

After installing and configuring the OS environment, we want to let the VPN server run as a system daemon and also will start up whenever the system boots up. To do this we create startup script for it:

```bash
sudo vi /etc/init.d/vpnserver

#!/bin/sh
# chkconfig: 2345 99 01
# description: SoftEther VPN Server
DAEMON=/usr/local/vpnserver/vpnserver
LOCK=/var/lock/subsys/vpnserver
TAP_ADDR=192.168.7.1

test -x $DAEMON || exit 0
case "$1" in
start)
$DAEMON start
touch $LOCK
sleep 1
/sbin/ifconfig tap_vpn $TAP_ADDR
;;
stop)
$DAEMON stop
rm $LOCK
;;
restart)
$DAEMON stop
sleep 3
$DAEMON start
sleep 1
/sbin/ifconfig tap_vpn $TAP_ADDR
;;
*)
echo "Usage: $0 {start|stop|restart}"
exit 1
esac
exit 0

sudo chmod +x /etc/init.d/vpnserver
sudo chkconfig vpnserver on
sudo service vpnserver start
```

Please note that in the script, we will config the tap interface *vpn* whenever the vpnserver starts up. After this you should see the vpnserver is up and running. It will start up automatically when the system restarts also. You can verify this by restarting the system once.

```bash
ps aux | grep vpnserver
root      8557  0.0  0.1  17520  1088 ?        S<s  07:24   0:00 /usr/local/vpnserver/vpnserver execsvc
root      8590  0.6  1.9 574932 19888 ?        S<l  07:24   0:00 /usr/local/vpnserver/vpnserver execsvc
ec2-user  8623  0.0  0.1 110428  1788 pts/0    S+   07:24   0:00 grep --color=auto vpnserver

sudo reboot

ps aux | grep vpnserver
root      8557  0.0  0.1  17520  1088 ?        S<s  07:24   0:00 /usr/local/vpnserver/vpnserver execsvc
root      8590  0.6  1.9 574932 19888 ?        S<l  07:24   0:00 /usr/local/vpnserver/vpnserver execsvc
ec2-user  8623  0.0  0.1 110428  1788 pts/0    S+   07:24   0:00 grep --color=auto vpnserver
```

## Manage SoftEther Server 

Up to this point, the VPN server is up and running, but it's not configured and we don't have any users. We use *SoftEther VPN Server Manager* to configure these. 

#### Download the manager and install

Go to the [download page](http://www.softether-download.com/en.aspx?product=softether) and select the right component.

![Download Page](download-manager.jpeg)

#### Connect to the VPN server as admin and setup password
After installing, open the SoftEther VPN Server Manager and create a new settings, fill in the name, host name, port number (443) and leave the password empty (Because it's your first time connecting). 

![New Connection](adminconnection.jpeg)

Once the connection is established, you will be prompt to set up a password:

![Set Password](setpassword.jpeg)

After you set up the password you will asked to configure the VPN server type, in our case here, we choose Remote Access VPN server:

#### Configure VPN server type
![Configure Server](vpntype.jpeg)

Now you will be prompt to name your Virtual Hub, and the DDNS hostname, which you can just leave as their default values. The next page you will see is the IPsec/L2TP/EtherIP/L2TPv3 Settings, select Enable L2TP Server Function (L2TP over IPsec) and type in the IPSec Pre-Shared Key.

![L2TP](l2tp.jpeg)

#### Configure the Local Bridge

At the main page, click on the *Local Bridge Settings* to bring up the settings page, selecte our hub and choose to use *Bridge with New Tap Device*, in the device name field type in "vpn" (rembemer we just created this tap in the above steps). When you are done click *Create Local Bridge* and you will see the local bridge created.

![Local Bridge](localbridge.jpeg)

#### Create a user

Now you're all set to establish the VPN connection, click on the *Manage Virtual Hub* button and you will see the manage users option:

![Manage Users](vpnuser.jpeg)

Add a user with password authentication (you can also add other types of authentication if needed), set up his password and click ok.

![Add a User](adduser.jpeg)


## Configure the VPN Client On MacOS

Now we have the VPN server up and running, and we have configured it to accept connections from a VPN client. We also created a user that are allowed to connect to the VPN. The next step is to test the connection to the VPN using a VPN client. 

Mac has a built-in support to IPsec/L2TP VPN so we don't need to install anything else but just do a few configurations to get it to work.

* Open System Preferences -> Network -> +:

![Add a User](macvpncreate.jpeg)

* Fill in the server address and your account name and click on the authentication settings, you can select *Show VPN status in the menu bar* if you want to see the status bar.

![Server and UserName](macvpnuser.jpeg)

* Fill in the password for the user and the pre-shared key for the IPsec:

![Set Password and Pre-shared Key](macvpnpassword.jpeg)

You're all set to connect to the VPN.

![VPN Connect](vpnconnect.jpeg)

![VPN Connected](vpnconnected.jpeg)

When the VPN is connected, ping to your VPN server using it's private IP and see whether it go through. If it works, try to ping to another private instance in the same VPC using it's private IP. (Note: The VPN Server Security Group has to allow incoming ICMP from your IP, the private instance has to allow ICMP from the VPN security group in order to get it to work).

```bash
ping -c 3 10.10.0.41
PING 10.10.0.41 (10.10.0.41): 56 data bytes
64 bytes from 10.10.0.41: icmp_seq=0 ttl=255 time=245.192 ms
64 bytes from 10.10.0.41: icmp_seq=1 ttl=255 time=244.973 ms
64 bytes from 10.10.0.41: icmp_seq=2 ttl=255 time=244.667 ms

--- 10.10.0.41 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 244.667/244.944/245.192/0.215 ms

ping -c 3 10.10.30.92
PING 10.10.30.92 (10.10.30.92): 56 data bytes
64 bytes from 10.10.30.92: icmp_seq=0 ttl=254 time=245.143 ms
64 bytes from 10.10.30.92: icmp_seq=1 ttl=254 time=245.158 ms
64 bytes from 10.10.30.92: icmp_seq=2 ttl=254 time=245.371 ms

--- 10.10.30.92 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 245.143/245.224/245.371/0.104 ms
```

## Conclusion

In this article, I introduced how to setup a VPN server using SoftEther VPN Server software on a AWS EC2 instance to enable L2TP/IPSec VPN connections from password authenticated user to the private instances in a AWS VPC. The key challenge is about setting of the DHCP server and static routing on the server to enable the Local Bridge mode for the SoftEther VPN Server and allow the VPN client to access private instances. Although I'm using linux as the VPN server and mac as the VPN client in this article, you can easily apply it to other combinations (linux + windows, windows + android for example) if you understand the idea between the configurations. Because SoftEther VPN Server has a lot more features in terms of VPN Protocol and authentication methods, you can refer to the detailed full documents on it's offcial site at [this link](https://www.softether.org/4-docs) if you're interested.

