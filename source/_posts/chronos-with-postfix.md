---
title: Configure Chronos to send failure notifications through Postfix
date: 2016-06-17 14:56:37
tags: 
  - Mesos 
  - Chronos
  - Postfix
  - Ansible
category: 
  - DevOps
---

Having a job scheduler without notification ability makes no sense because you never know what's going on with it and whether it is running correctly. Luckily Chronos has built-in support for sending out emails when a job is failed or interrupted, which means all we need is to have a mail server that is able to send out emails.

My solution is to set up the mail agent myself instead of using a existing mailing service like Gmail. My reasons are:
1. I don't want to have the potention to leak my account password.
2. I want to have a custom domain in the sender's email address.
3. Setting up an email transfer agent is not that hard.

And here comes in postfix, which is a very popular free open source MTA. It's estimated that 25% of the public mail servers use it.

### Install and configure postfix

I use [ansible](https://www.ansible.com/) playbook to install and configure postfix, the environment is AWS Linux AMI (based on Centos 6).

#### Disable sendmail service and install postfix
On AWS Linux AMI instances, the **sendmail** service is normally enabled and started by default, because it's binded to port 25, we need to stop and disable it first so that port 25 will be freed to use by postfix.
```yml
- name: make sure sendmail service is not running and disabled to free port 25
  become: yes
  become_method: sudo
  service: name=sendmail state=stopped enabled=no
  tags:
    - postfix
- name: install postfix
  become: yes
  become_method: sudo
  yum: name=postfix state=latest
  tags:
    - postfix
```

#### Configure postfix
The configuration of postfix is the most complicated and important part to get it work properly. The following is what I have in the configuration file.
```
soft_bounce             = no
queue_directory         = /var/spool/postfix
command_directory       = /usr/sbin
daemon_directory        = /usr/libexec/postfix
mail_owner              = postfix
mynetworks              = 127.0.0.0/8,172.0.0.0/8

myhostname              = mail.yourdomain
mydomain                = yourdomain
relay_domains           = yourdomain, gmail.com

mydestination           = $myhostname, localhost
unknown_local_recipient_reject_code = 550

mynetworks_style        = host
mailbox_transport       = lmtp:unix:/var/lib/imap/socket/lmtp
local_destination_recipient_limit       = 300
local_destination_concurrency_limit     = 5
recipient_delimiter=+

virtual_alias_maps      = hash:/etc/postfix/virtual

header_checks           = regexp:/etc/postfix/header_checks
mime_header_checks      = pcre:/etc/postfix/body_checks
smtpd_banner            = $myhostname

debug_peer_level        = 2
debugger_command =
         PATH=/bin:/usr/bin:/usr/bin:/usr/X11R6/bin
         xxgdb $daemon_directory/$process_name $process_id & sleep 5

sendmail_path           = /usr/sbin/sendmail.postfix
newaliases_path         = /usr/bin/newaliases.postfix
mailq_path              = /usr/bin/mailq.postfix
setgid_group            = postdrop
html_directory          = no
manpage_directory       = /usr/share/man
sample_directory        = /usr/share/doc/postfix-2.3.3/samples
readme_directory        = /usr/share/doc/postfix-2.3.3/README_FILES

smtpd_sasl_auth_enable          = yes
smtpd_sasl_application_name     = smtpd
smtpd_recipient_restrictions    = permit_sasl_authenticated,
                                  permit_mynetworks,
                                  reject_unauth_destination,
                                  reject_non_fqdn_sender,
                                  reject_non_fqdn_recipient,
                                  reject_unknown_sender_domain,
                                  reject_unknown_recipient_domain,
                                  reject_unauth_pipelining,
                                  reject_rbl_client zen.spamhaus.org,
                                  reject_rbl_client bl.spamcop.net,
                                  reject_rbl_client dnsbl.njabl.org,
                                  reject_rbl_client dnsbl.sorbs.net,
                                  permit

smtpd_sasl_security_options     = noanonymous
smtpd_sasl_local_domain         =
broken_sasl_auth_clients        = yes

smtpd_helo_required             = yes
```
You have to set **myhostname** and **mydomain** field respectively according to the domain you want to use, and set the **replay_domains** properly so that emails can reach the receiver, e.g. if you want to be able to send email to a gmail user, you need to add **gmail.com** to **relay_domains**. In addition, if you're running Chronos in docker containers using Marathon, make sure that **reject_invalid_hostname** and **reject_non_fqdn_hostname** are not presented in the **smtpd_recipient_restrictions**, this is because Chronos built-in email client doesn't use a fqdn hostname, the hostname will be the container's short ID. Finally, you have to make sure **mynetworks** contains the CIDR block of your senders' address, e.g. if you run chronos in docker with default docker networking configuration, you have to add 172.0.0.0/8 to **mynetworks**, otherwise the sending request from chronos will be blocked.

#### Set up virtual alias maps and body checks file
As we set "virtual_alias_maps      = hash:/etc/postfix/virtual" in the configuration file, we need to prepare the virtual file with proper usernames and domains.
```
info@yourdomain info\@yourdoamin
```
Once the file is set up, run postmap to turn the file into lookup table.
```yml
- name: set up user database
  become: yes
  become_method: sudo
  copy: src=./virtual dest=/etc/postfix/virtual force=yes
  tags:
    - postfix
    - postfix-config
- name: turn virtual file into lookup table
  become: yes
  become_method: sudo
  command: /usr/sbin/postmap /etc/postfix/virtual
  tags:
    - postfix
    - postfix-config
```
As we set "mime_header_checks      = pcre:/etc/postfix/body_checks" in the configuration file, we need to prepare the file in place.
```yml
- name: set up body checks file
  become: yes
  become_method: sudo
  copy: src=./body_checks dest=/etc/postfix/body_checks
  tags:
    - postfix
    - postfix-config
```

#### Start and enable postfix service.
```yml
- name: start postfix and enable into
  become: yes
  become_method: sudo
  service: name=postfix state=started enabled=yes
  tags:
    - postfix
    - postfix-config
```

### Configure chronos to enable email notification
The related parameters to configure chronos for failure notifcations are --mail_from, --mail_user, --mail_password, --mail_server and --mail_ssl, in our case, we don't have to set up --mail_password and --mail_ssl. Set the following parameters based on your domain name:
```
--mail_from youruser@yourdomain
--mail_server postfix_server_ip/domain:25
--mail_user youruser@yourdomain
```
On the other hand, for each of the chronos job definition file, add owner field into it:
```
"owner": "another_user@yourdomain,user@gmail.com" 
```

### Verification and conclusion
Up to this point, we can test whether this thing wors or not. Set up a job that will fail purposely and run it manually through API or the chronos UI. And you should receive emails like this:
```
'2016-06-17T04:41:19.171Z'. Retries attempted: 2.
Task id: ct:1466138472279:0:taskname:


The scheduler provided this message:

Docker container run error: Container exited on error: exited with status 1
```
Up to this point, we're all set to have chronos report errors. The full ansible code can be found at https://github.com/WUMUXIAN/microservices-infra/tree/master/aws. Now let's hope all our jobs run well and we will never receive this kind of emails after testing. :)


