---
title: MySQL load testing
date: 2019-02-26 13:51:33
tags: MySQL
category: Database
---

This post aims to do some testing on MySQL server in terms of its capacity and performance, when the number of records in each table grows into multi-million scale. In reality, not many applications actually have this amount of data to store, and trust me, if your application is ever going to have this amount of data, you better simulate what would happen before it actually happen to you and caught you off guard.

It's always more useful to see how it actual looks like by running something in real other than just reading it from paper. So this post will guide you through some tests and primarily focus on the following topics:

- How much time does it take to inserting multi-million records into a table.
  - Is there any tricks to speed up inserting?
  - How big difference it will have between inserting into a small table (small columns) and big table (big columns)
- How big is the difference with having index and not when it comes to multi-million records.
- How much time does it take to add a new index on a multi-million records table.
- How much time does it take introduce a foreign key constraint between two multi-million records tables.

### Get Started
Let's get started by having an instance and a MySQL server running. The instance I'm having has the following specs:

```
CPU: 48 cores
Memory: 256G
Disk: 1.8T HDD
```

Now run MySQL server using Docker:
```bash
docker run -d -p 3306:3306 --name mysql-testing --restart=always \
	-e MYSQL_ROOT_PASSWORD=password -v $PWD/data:/var/lib/mysql mysql:5.7.24
```

### Creating database schema
For testing, we are going to create the following tables:
- event: a event contains x sitting tables.
- sitting_table: a sitting table contains x registrants.
- registrants: a registrant contains it's contacts and a face feature.

The following scripts create the DB and the tables:

```sql
CREATE DATABASE `load_test_db` DEFAULT CHARACTER SET latin1 COLLATE latin1_general_ci;

CREATE TABLE `load_test_db`.`event` (
  `id` CHAR(36) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`id`));

CREATE TABLE `load_test_db`.`sitting_table` (
  `id` char(36) NOT NULL,
  `name` varchar(45)NOT NULL,
  PRIMARY KEY (`id`));

CREATE TABLE `load_test_db`.`registrant` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NOT NULL,
  `features` BLOB NULL,
  PRIMARY KEY (`id`));

```

### Inserting 5 million events

#### Inserting one by one.
```sql
drop procedure insert_events;
delimiter #
create procedure insert_events()
begin
declare v_max int unsigned default 5000000;
declare v_counter int unsigned default 0;

  truncate table event;
  -- start transaction;
  while v_counter < v_max do
    insert `event`(id, name) values (uuid(), random_bytes(45));
    -- we make a commit for every 50 inserts
--     if v_counter % 50 = 0 then
-- 		commit;
--         start transaction;
-- 	end if;
    set v_counter=v_counter+1;
  end while;
--   commit;
end #

delimiter ;
call insert_events();
```
> Please note that if you are using MySQL WorkBench to run the script, you need to set the following to a large number in order not to have a timeout:
Edit->Preferences->SQL Editor->DBMS connection read time out (in seconds)
I set it to 10800 (3 hours).

During the test you will find it's extremely slow:

![inserting speed with one to one approach](inserting_speed_1.png)

The average inserting speed is at ~70/s. So to insert 5 million records, we'll need 1190 minutes = 19 hours.

This is not acceptable, so let's stop it and do some optimizations to it.

#### Inserting in batches (bulk insert)
```sql
drop procedure insert_events;
delimiter #
create procedure insert_events()
begin
declare v_max int unsigned default 5000000;
declare v_counter int unsigned default 0;

  truncate table event;
  start transaction;
  while v_counter < v_max do
    insert `event`(id, name) values (uuid(), random_bytes(45));
    -- we make a commit for every 500 inserts
    if v_counter % 500 = 0 then
		commit;
        start transaction;
	end if;
    set v_counter=v_counter+1;
  end while;
  commit;
end #

delimiter ;
call insert_events();
```
What we did above is to use transactions to do bulk insert, we commit for every 500 insertions. And now it's much much faster:

![inserting speed with bulk insertion](inserting_speed_2.png)

We can see that now we are writing ~1MB/s to disk compared to previously 60KB/s, the speed goes up about ~20 times. We now only need <1 hour for inserting 5 million records.

#### Improving the inserting event more.
Actually we can tweak the server parameters to improve the inserting speed even more. Let's restart the MySQL server and this time set the following parameters:

```bash
docker run -d -p 3306:3306 --name mysql-testing --restart=always \
	-e MYSQL_ROOT_PASSWORD=password -v $PWD/data:/var/lib/mysql mysql:5.7.24 \
  --innodb-doublewrite=0 --innodb_flush_log_at_trx_commit=0 \
  --innodb_log_file_size=1G --innodb_log_buffer_size=256M \
  --innodb_buffer_pool_size=128G --innodb_write_io_threads=16 \
  --innodb_support_xa=0 --max_allowed_packet=16M
```
Let's explain the settings one by one:
- innodb-doublewrite: set this to 0 so that innodb won't write the data twice to disk.
- innodb_flush_log_at_trx_commit: set this to 0 give a better performance but could lose data during crash.
- log-bin: this is used for backup and replication, so we disable it to improve performance.
- innodb_log_file_size: larger log file reduces checkpointing and write I/O.
- innodb_log_buffer_size: larger buffer size reduces write I/O to transaction logs.
- innodb_buffer_pool_size: this will cache frequently read data, **you should set this to ~50% of you system memory, in my case, 128GB**
- innodb_write_io_threads: each thread can handle up to 256 pending I/O requests. Default for MySQL is 4, 8 for Percona Server. Max is 64, we set to 16.
- innodb_support_xa: disable two pharse commit to increase performance.

In addition, we disable all consistency checks during the insertion:
```sql
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET AUTOCOMMIT = 0;
call insert_events();
SET UNIQUE_CHECKS = 1;
SET FOREIGN_KEY_CHECKS = 1;
```
Now let's run again and see the result:

![inserting speed with bulk insertion and server configured](inserting_speed_3.png)

I was actually able to insert the 5 million records into DB in 145 seconds. The speed is at ~35000 inserts/s.

#### A final push.
If you notice that in our procedure to insert, we are not actually using the real **bulk insert** that MySQL supports, which is:
```sql
insert `event`(id, name) values
    (uuid(), random_bytes(45)),
    (uuid(), random_bytes(45)),
    (uuid(), random_bytes(45)),
    ...    
    (uuid(), random_bytes(45)),
    (uuid(), random_bytes(45)),
    (uuid(), random_bytes(45));
```
If we change it to this way, the speed will be even higher:

![inserting speed with real bulk insertion and server configured](inserting_speed_4.png)

I completed the insertion of 5 million records in 85 seconds, which yells a ~70000 inserts/s. I think this is pretty much what we can do, to further improve the performance, we will need to use a SSD instead of HDD. Once having the chance I'll do the test.
