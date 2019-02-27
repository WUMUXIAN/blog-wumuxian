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

This server sits in the same network with my machine, which is the MySQL client that sends out the insertion commands.

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
  `id` INT(11) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`id`));

CREATE TABLE `load_test_db`.`sitting_table` (
  `id` INT(11) NOT NULL,
  `event_id` INT(11) NOT NULL,
  `name` varchar(45)NOT NULL,
  PRIMARY KEY (`id`));

CREATE TABLE `load_test_db`.`registrant` (
  `id` INT NOT NULL,
  `sitting_table_id` INT(11) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  `features` BLOB NULL,
  PRIMARY KEY (`id`));

```

### Inserting 5 million records into event table

#### Inserting one by one.
```sql
drop procedure insert_events;
delimiter #
create procedure insert_events()
begin
declare v_max int unsigned default 5000000;
declare v_counter int unsigned default 0;

  truncate table event;
  while v_counter < v_max do
    insert `event`(id, name) values (v_counter, "xxxxxxxxxxxxxxxxxxxx");
    set v_counter=v_counter+1;
  end while;
end #

delimiter ;
call insert_events();
```
> Please note that if you are using MySQL WorkBench to run the script, you need to set the following to a large number in order not to have a timeout:
Edit -> Preferences -> SQL Editor -> DBMS connection read time out (in seconds)
I set it to 10800 (3 hours).

During the test you will find it's extremely slow:

![inserting speed with one to one approach](inserting_speed_1.png)

The average inserting speed is at ~70 inserts/s. So to insert 5 million records, we'll need 1190 minutes = 19 hours.

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
    insert `event`(id, name) values (v_counter, "xxxxxxxxxxxxxxxxxxxx");
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

We can see that now we are doing ~15000 inserts/s compared previously ~70 inerts/s, The speed goes up about ~200 times. We now only need ~356 seconds for inserting 5 million records.

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

The speed now goes up to 70000 inserts/s, which is 4.5 times faster than the previous database settings. The insertion takes about 70s to finish.

#### A final push.
If you notice that in our procedure to insert, we are not actually using the real **bulk insert** that MySQL supports, which is:
```sql
drop procedure insert_events;
delimiter #
create procedure insert_events()
begin
declare v_max int unsigned default 5000000;
declare v_counter int unsigned default 0;
declare v_global_counter int unsigned default 0;

  truncate table event;
  start transaction;
  while v_counter < v_max/40 do
    insert `event`(id, name) values
    (v_global_counter+1, 'xxxxxxxxxxxxxxxxxxxx'),
    (v_global_counter+2, 'xxxxxxxxxxxxxxxxxxxx'),
    (v_global_counter+3, 'xxxxxxxxxxxxxxxxxxxx'),
    (v_global_counter+4, 'xxxxxxxxxxxxxxxxxxxx'),
    .....
    (v_global_counter+40, 'xxxxxxxxxxxxxxxxxxxx');
    set v_global_counter = v_global_counter + 40;
    -- we make a commit for every 25 bulk inserts
    if v_counter % 25 = 0 then
		commit;
        start transaction;
	end if;
    set v_counter=v_counter+1;
  end while;
  commit;
end #

delimiter ;
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET AUTOCOMMIT = 0;
call insert_events();
SET UNIQUE_CHECKS = 1;
SET FOREIGN_KEY_CHECKS = 1;
select count(1) from event;
```
If we change it to this way, the speed will be even higher:

![inserting speed with real bulk insertion and server configured](inserting_speed_4.png)

The speed now is at ~190000 inerts/s, inserting 5 million records only takes ~26 seconds. I think this is pretty much what we can do, to further improve the performance, we will need to use a SSD instead of HDD. Once having the chance I'll do the test.

> One thing that bothers me still is, the cap at writing speed to disk is at about **25MB/s**, which does not reach the capacity of the HDD too. It seems that MySQL's design inherently limit the writing speed to a certain extent. I am not quite sure and I hope someone can answer my question.

### Inserting 15 million records into sitting_table table.
We already know the insertion performance and how to optimize in the previous section. There are two things that I am interested in:
1. How fast is insert ... select from ...
2. How big is the difference between with/without foreign key constraint during insertion.
3. Is the speed consistent, in other words, does the time required for insertions increase linearly when the total number of records to insert increase.
4. How much time does it take to add an index to a table that contains multi-million records.

#### Inserting using select from.
```sql
drop procedure insert_sitting_tables;
delimiter #
create procedure insert_sitting_tables()
begin
  truncate table sitting_table;
  insert into sitting_table(id, event_id, name) select id, id as event_id, 'xxxxxxxxxxxxxxxxxxxx' as name from event;
end #

delimiter ;
call insert_sitting_tables();

select count(1) from sitting_table;
```
This gives us about ~170000 inserts/s, it's quite good performance, which answers question 1 in a way. Now to answer question 3, let's insert 3 tables per event instead of one:
```sql
begin
  truncate table sitting_table;
  insert into sitting_table(id, event_id, name) select id, id as event_id, 'xxxxxxxxxxxxxxxxxxxx' as name from event;
  insert into sitting_table(id, event_id, name) select id, id as event_id, 'xxxxxxxxxxxxxxxxxxxx' as name from event;
  insert into sitting_table(id, event_id, name) select id, id as event_id, 'xxxxxxxxxxxxxxxxxxxx' as name from event;
end #
```
The result yells to the same ~170000 inserts/s, which indicates that the time needed to insert is quite linear as the number of records to insert increases.
In total, it took 88 seconds to finish.

#### Inserting with/without indexes and foreign key checks.
To compare, let's now add index and foreign key constraint for the sitting_table, as it has a one-to-many relationship with event table.
```sql
ALTER TABLE `load_test_db`.`sitting_table`
ADD INDEX `idx_event_id` (`event_id` ASC);
ALTER TABLE `load_test_db`.`sitting_table`
ADD CONSTRAINT `fk_sitting_table_event_id`
  FOREIGN KEY (`event_id`)
  REFERENCES `load_test_db`.`event` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
```
Since we already have 15 million records in sitting_table, adding an index should take a great deal of time, which is exactly what we want to find out, for question 4. The result shows the following:
- 27 seconds to apply the index for column `event_id`;
- 129 seconds to create the foreign key constraint;

This suggests that adding index and constraint to a heavy table is a very expensive operation and we should be careful about it, in my opinion this kind of operation should only be carried out when the database is not serving any production requests (during maintenance).

Now let's truncate the table and re-do the insertion.
```sql
call insert_sitting_tables();
```
It takes 508s to do the insertion compared to 103s when index and constraint do not exist. Now let's do some maths:
- When I did insertions first then add index and constraint, it used 85 + 27 + 129 = 261s.
- When I introduce the index and constraint first and do insertions, it used 134s.

This is quite surprising to me:
1. Adding constraint takes so much time.
2. When the primary key and indexes are simple and sorted well, inserting them in is quite fast.
3. Looks like having index and constraint first and then insert is not that bad if index column is sorted, only ~5 times slower.

The above conclusion answers the question 4 I mentioned in the beginning of this section.

### Inserting 30 million records into registrant table.

Firstly let's create the procedure to insert. We will insert 1 registrant per table first and see how fast it runs. Since for each registrant, we will store his/her face features, which is a 1024 bytes blob.
```sql
drop procedure insert_registrant;
delimiter #
create procedure insert_registrant()
begin
declare feats varbinary(1024);
  truncate table registrant;
  set feats = random_bytes(1024);
  insert into registrant(id, sitting_table_id, name, features) select id, id as sitting_table_id, 'xxxxxxxxxxxxxxxxxxxx' as name, feats as features from sitting_table;
end #

delimiter ;
call insert_registrant();

select count(1) from registrant;
```

Now we can see that it's quite slow, inserting 15 million rows of registrant took 950 seconds, which is 16 minutes. The speed is reduced by more than 10 times, compared to inserting to a table that does not contain large column with the same amount of rows. On a separate note, I also tried to change the features column to a varbinary(1024) instead of blob, because varbinary is stored inline with the row but blob is not. However the speed is not affected at all.

![inserting speed with select ... from ... and large column](inserting_speed_5.png)

> Now the actual writing speed goes up to **35MB/s**, compared to **25MB/s** previously writing small tables. However since each row to write now is so significantly larger than previously, the overall inerts/s still reduce like crazy.

After the benchmarking, and assuming that the speed is linear, we can now insert 30 million rows. It will take ~30 minutes if our theory is correct. So take a cup of coffee or go eat something while letting it run.

### Query from a multi-million rows table with/without index.
Now we have a database with 3 tables in place.
- event: 5 million records.
- sitting_table: 15 million records.
- registrant: 30 million records.
Since all the bulk insertion is finished, let's now restart the server with default settings and do some experiments on performing various CURD operations.
Let's do some query now to see how it much time it takes when you have index or not have index. Let's use the registrant table.
```sql
select * from registrant where sitting_table_id = 5;
```
It turned out to take 44 seconds to get the result, since no index is on sitting_table_id thus it required a full table scan. Now let's add index for sitting_table_id and try again.
```sql
ALTER TABLE `load_test_db`.`registrant`
ADD INDEX `idx_sitting_table_id` (`sitting_table_id` ASC);
```
This alone took about 123 seconds to complete, now let's query again.
```sql
select * from registrant where sitting_table_id = 5;
```
It only took 1.8 milliseconds to get the result.

We can conclude that, at the scale of multi-million rows, query something using a column that does not have index on it is not acceptable, but with index, it's still very fast.

### Insert/Update/Delete operations on a multi-million rows table.
Let's see how fast it is to insert a row into the registrant table.
```sql
insert into registrant (id, sitting_table_id, name, features) values (30000001, 1, "test name", random_bytes(1024));
```
It took about 30 ms to run, which is still acceptable.
```sql
update registrant set name = "test name 1" where id = 30000001;
```
It took about 28 ms to finish, which is similar to insertion.
```sql
delete from registrant where id = 30000001;
```
It took about 28 ms to finish, which is similar to insertion as well.

### Conclusion
After running the above tests, we can come up with the following take-aways:
1. To achieve massive insertion speed, we need to configure the database settings to trade-off consistency, crash resistence for speed.
2. To achieve massive insertion speed, we can't do insert record by record, we need to bulk insert.
3. A big table (contains big columns) take much more time to insert, compared to smaller table (no big columns), even though the writing speed can be pushed higher.
4. Adding index is roughly at about 540000 rows/s, for integer index type, tested on a 30 million rows table.
5. Adding foreign constraint is a more expensive operation than adding index.
6. Query using index yells a very good speed against multi-million rows table, at <2 ms. However, without index the speed is not acceptable as it scan through the whole table.
7. Inserting/Updating/Deleting operation on a table contains multi-million rows is significantly slower (10 times) than select operations with index against it. But the speed is still acceptable.
