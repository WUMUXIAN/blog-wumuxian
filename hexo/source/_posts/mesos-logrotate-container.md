---
title: Setup Mesos to rotate containers' stdout/stderr logs
date: 2016-05-25 14:19:43
tags: 
  - Mesos
  - Docker
  - Logging
category: 
  - Infrastructure
---

## The problem I'm facing
As we all know, mesos will log the the stdout and stderr of any containers started as a task into the sandbox as plain text files, which is the work directory of the corresponding slave.
```
root ('--work_dir')
|-- slaves
|   |-- latest (symlink)
|   |-- <agent ID>
|       |-- frameworks
|           |-- <framework ID>
|               |-- executors
|                   |-- <executor ID>
|                       |-- runs
|                           |-- latest (symlink)
|                           |-- <container ID> (Sandbox!)
```
After running some tasks for a while, I found out that the stdout/stderr logs are never rotated and they're filling up the slaves' disk space. This is certainly not what I wanted.

## Mesos now support log rotation for the stdout/stderr logs, Hallelujah!
Very luckily, mesos has supported log rotation for the containers' stdout/stderr since 0.27.0 to address the shortcoming. But it's not the default behaviour, you need to explicitly specify some parameters when launching the mesos slave to enable it. Here're the steps:

### Step 1: Put a json file containing the following content into anywhere of the machine but not /etc/mesos-slave/, in my case, I put it in /etc/ and name it as mesos-slave-modules.json.
```bash
vi /etc/mesos-slave-modules.json
{
   "libraries": [
     {
       "file": "/usr/lib/liblogrotate_container_logger.so",
       "modules": [
         {
           "name": "org_apache_mesos_LogrotateContainerLogger",
           "parameters": [
             {
               "key": "launcher_dir",
               "value": "/usr/libexec/mesos"
             }
           ]
         }
       ]
     }
   ]
 }
```
The json file specifies the modules that we want to load, where to find the library and where to find the executable. In this case, I load the module "org_apache_mesos_LogrotateContainerLogger" from the "liblogrotate_container_logger.so" library and tell mesos that the launching binary is in "/usr/libexec/mesos". 

### Step 2: Start/Restart the mesos-slave process with the following configurations.
```bash
/usr/sbin/mesos-slave --container_logger=org_apache_mesos_LogrotateContainerLogger --modules=/etc/mesos-slave-modules.json
```
This will set the "modules" to point to the json file we created at step 1, and set the "container_logger" to the rotation logger's name.

### Step 3: Retart you existing tasks.
Please note that your old tasks won't have log rotation immediately. You need to restart them to take effect, any new coming tasks created will have the log rotation.
```
mode       nlink   uid     gid     size    mtime       
-rw-r--r--  1      root    root    169 B   May 25 13:52     stderr                  Download
-rw-r--r--  1      root    root    245 B   May 25 13:52     stderr.logrotate.conf   Download
-rw-r--r--  1      root    root    9 MB    May 25 14:26     stdout                  Download
-rw-r--r--  1      root    root    245 B   May 25 13:52     stdout.logrotate.conf   Download
```
 
