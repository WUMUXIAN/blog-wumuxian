---
title: What happens when Elasticsearch runs out of heap
date: 2019-02-28 17:21:35
tags:
- Elasticsearch
- JVM
category: Devops
---

On a normal working day, one of my colleagues suddenly called me and asked me to check what's going on with the Elasticsearch server deployed on one of our customer's server. According to him, the behavior has been very weird:
- The server is very unstable, the elastic-head UI loses the connection now and then.
- There's no data been written to the Elasticsearch for the last a few days.

The initial guess he had was the storage is full so no more indices can be written in. Since he has no clue I started to look into it.

### The journey to find the root cause.

I firstly tried to see whether disk is fully used, it turned out that total documents stored in the Elasticsearch cluster is only 3.5G, it's nothing compared to the 11T hard disk, so it can not be the reason.

So I started to look into the logs, the log file has grow surprisingly into 1.3G, apparently something is going on and spamming the log. Scanning through the log file I found it interesting to see that numerous amount of logs regarding garbage collection are presented, and it prints almost non-stop. That's exactly the reason why the log file is so large. Now this means the GC is trying to collect garbage almost non-stop. But why is that? Could it be something that caused a memory leak thus making the GC super busy?

After scanning through the log file, I found no clue. Also looked on the Internet, some people had the similar problem caused by bulk API calls, however it's not relevant to our case. Restarting the whole server also does not help. Always it made the server start to accept incoming request with a very slow response. Checking the CPU usage I found that the Elasticsearch is already the top CPU cycle consumer amongst all the application.

The next thing and final thing I came to suspect is heap size.Since GC is about the heap, if the GC is happening so often, could it be the heap size full?

```bash
curl -X GET 'http://192.168.0.148:9200/_cat/nodes?h=heap*&v'
heap.current heap.percent heap.max
     959.5mb           97  989.8mb
```
Bingo!

I could not believe that Elasticsearch is configured to run with the default heap size, which is only 1G. If you read the official documents regarding heap size, it says clearly that:

> When moving to production, it is important to configure heap size to ensure that Elasticsearch has enough heap available.

That's because 1G is definitely no enough for any production setup and this incident showed exactly what will happen if you do leave it to 1G.

### Conclusion.

The issue we had on the Elasticsearch server is a very newbie error regarding the configuration of the heap size. However it gave a chance to me to see what will happen when no enough heap is allocated for Elasticsearch to work: It will simply make it half-dead. So let's review the rules of setting heap size again for Elasticsearch:

* Set the minimum heap size (Xms) and maximum heap size (Xmx) to be equal to each other.
* The more heap available to Elasticsearch, the more memory it can use for caching. But note that too much heap can subject you to long garbage collection pauses.
* Set Xmx to no more than 50% of your physical RAM, to ensure that there is enough physical RAM left for kernel file system caches.
* Don’t set Xmx to above the cutoff that the JVM uses for compressed object pointers (compressed oops); the exact cutoff varies but is near 32 GB. You can verify that you are under the limit by looking for a line in the logs like the following:
heap size [1.9gb], compressed ordinary object pointers [true]
Even better, try to stay below the threshold for zero-based compressed oops; the exact cutoff varies but 26 GB is safe on most systems, but can be as large as 30 GB on some systems. You can verify that you are under the limit by starting Elasticsearch with the JVM options -XX:+UnlockDiagnosticVMOptions -XX:+PrintCompressedOopsMode and looking for a line like the following:

```
heap address: 0x000000011be00000, size: 27648 MB, zero based Compressed Oops
showing that zero-based compressed oops are enabled instead of

heap address: 0x0000000118400000, size: 28672 MB, Compressed Oops with base: 0x00000001183ff000
```
