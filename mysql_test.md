
### Insert 1,000 projects.

```mysql
drop procedure if exists insert_projects;
DELIMITER $$
create procedure insert_projects(user_id varchar(45), company_id varchar(40), total_num int)
begin
	declare num int;
	declare now varchar(40);
	declare time_stamp bigint;
    set num = 1;
    set now = now();
    set time_stamp = unix_timestamp() * 1000;
    while num <= total_num do
        insert into project(id, user_id, company_id, name, description, updated, created, status) values(UUID(), user_id, company_id, CONCAT('project', num), CONCAT('project', num), time_stamp+num, now, 3);
        set num = num + 1;
    end while;
end $$
DELIMITER ;

call insert_projects('mw@tectusdreamlab.com', '089c4186-9598-aff8-8781-4f7d5274c49d', 1000)
```


### Insert 500,000 topics, because we assume ~500 topics per project.

```mysql
drop procedure if exists insert_topics;
DELIMITER $$
create procedure insert_topics(user_id varchar(45), project_num int, topic_num_per_project int)
begin
	declare num int;
	declare global_counter int;
	declare topic_num int;
	declare time_stamp bigint;
    set num = 1;
    set global_counter = 1;
    set time_stamp = unix_timestamp() * 1000;
    set @updated := 0;
    while num <= project_num do
    	select @project_id := id, @updated := updated from project where updated > @updated order by updated limit 1;
    	set topic_num = 1;
    	while topic_num <= topic_num_per_project do
    		insert into topic(id, project_id, name, description, updated, updated_user, created, pdf_marker, markers, defect, tools) values(UUID(),@project_id,CONCAT('topic', global_counter), CONCAT('topic', global_counter), time_stamp+global_counter, user_id,time_stamp+global_counter,'{}','[{"elementID":"3WOJOwLlz5WhD5$LzpPRBr","worldCoordinates":{"x":-52.65388,"y":180.42688,"z":-0.10466739},"localCoordinates":{"x":0,"y":0,"z":0},"worldNormal":{"x":0.25881773,"y":-0.96592176,"z":-5.757343e-08},"localNormal":{"x":0,"y":0,"z":0}}]','{"locationID":"1000","typeID":"1000"}','101,103,105');
    		set topic_num = topic_num + 1;
    		set global_counter = global_counter + 1;
    	end while;
        set num = num + 1;
    end while;
end $$
DELIMITER ;

call insert_topics('mw@tectusdreamlab.com', 1000, 500);
```


### Insert 10,000,000 topic feed items, because we assume ~20 topic feed items per topic

```mysql
drop procedure if exists insert_topic_feed_items;
DELIMITER $$
create procedure insert_topic_feed_items(user_id varchar(45), topic_num int, feed_items_per_topic int)
begin
	declare num int;
	declare global_counter int;
	declare feed_items_num int;
	declare time_stamp bigint;
    set num = 1;
    set global_counter = 1;
    set time_stamp = unix_timestamp() * 1000;
    set @updated := 0;
    while num <= topic_num do
    	select @topic_id := id, @project_id := project_id, @updated := updated from topic where updated > @updated order by updated limit 1;
    	set feed_items_num = 1;
    	while feed_items_num <= feed_items_per_topic do
    		insert into topic_feed(id, topic_id, project_id, system, principal, action, resource, created_time, updated_time, updated) values(UUID(), @topic_id, @project_id, 1, user_id, 2, '{"status":[3,4]}', time_stamp + global_counter, time_stamp + global_counter, time_stamp + global_counter);
    		set global_counter = global_counter + 1;
    		insert into topic_feed(id, topic_id, project_id, system, principal, action, resource, created_time, updated_time, updated) values(UUID(), @topic_id, @project_id, 0, user_id, 6, '{}', time_stamp + global_counter, time_stamp + global_counter, time_stamp + global_counter);
    		set global_counter = global_counter + 1;
    		set feed_items_num = feed_items_num + 2;
    	end while;
        set num = num + 1;
    end while;
end $$
DELIMITER ;

call insert_topic_feed_items('mw@tectusdreamlab.com', 500000, 20);
```


### For all the above feed items that have attachments, we insert them, it 5,000,000 attachments in total

```mysql
drop procedure if exists insert_topic_feed_attachments;
DELIMITER $$
create procedure insert_topic_feed_attachments()
begin
	declare num int;
	set @updated := 0;
	set @topic_feed_id := "";
	select @total_count := count(*)/2 from topic_feed;
	set num = 1;
	while num <= @total_count do
		select @topic_feed_id := id, @updated := updated from topic_feed where updated > @updated order by updated limit 1, 1;
		insert into topic_feed_attachment(id, topic_feed_id, attachment_file_id, type) values(UUID(), @topic_feed_id, '55ece83d-cf69-0d97-d4a1-776c92b06576', 2);
		set num = num + 1;
	end while;
end $$
DELIMITER ;

call insert_topic_feed_attachments();
```


### Insert 5,000,000 topic feed mentions, because we estimate half of the feed item has 1 mention

```mysql
drop procedure if exists insert_topic_feed_mention;
DELIMITER $$
create procedure insert_topic_feed_items(user_id varchar(45), topic_num int, feed_items_per_topic int)
begin
	declare num int;
	declare global_counter int;
	declare feed_items_num int;
	declare time_stamp bigint;
    set num = 1;
    set global_counter = 1;
    set time_stamp = unix_timestamp() * 1000;
    set @updated := 0;
    while num <= topic_num do
    	select @topic_id := id, @project_id := project_id, @updated := updated from topic where updated > @updated order by updated limit 1;
    	set feed_items_num = 1;
    	while feed_items_num <= feed_items_per_topic do
    		insert into topic_feed(id, topic_id, project_id, system, principal, action, resource, created_time, updated_time, updated) values(UUID(), @topic_id, @project_id, 1, user_id, 2, '{"status":[3,4]}', time_stamp + global_counter, time_stamp + global_counter, time_stamp + global_counter);
    		set global_counter = global_counter + 1;
    		insert into topic_feed(id, topic_id, project_id, system, principal, action, resource, created_time, updated_time, updated) values(UUID(), @topic_id, @project_id, 0, user_id, 6, '{}', time_stamp + global_counter, time_stamp + global_counter, time_stamp + global_counter);
    		set global_counter = global_counter + 1;
    		set feed_items_num = feed_items_num + 2;
    	end while;
        set num = num + 1;
    end while;
end $$
DELIMITER ;

call insert_topic_feed_items('mw@tectusdreamlab.com', 500000, 20);
```

Some key findings in MySQL indexes.

- If you don't have combined indexes for the columns you use in the where query, only one of the indexes will be used, determined by the engine itself, you can specify which index to use by 'use index' or 'force index'. Use `EXPLAIN` to check whether the right indexes are used.

- select * from xxx where xxxx order by limit 'limits'; the limit part always comes the last, so don't expect to speed up the query by giving a very low limit. The speed relies only on whether the correct index/indexes are used.

- Indexes size can be bigger than data size sometimes.

- Every InnoDB table has a special index called the clustered index where the data for the rows is stored. Typically, the clustered index is synonymous with the primary key. When you define a PRIMARY KEY on your table, InnoDB uses it as the clustered index. Define a primary key for each table that you create. If there is no logical unique and non-null column or set of columns, add a new auto-increment column, whose values are filled in automatically. If you do not define a PRIMARY KEY for your table, MySQL locates the first UNIQUE index where all the key columns are NOT NULL and InnoDB uses it as the clustered index. If the table has no PRIMARY KEY or suitable UNIQUE index, InnoDB internally generates a hidden clustered index named GEN_CLUST_INDEX on a synthetic column containing row ID values. The rows are ordered by the ID that InnoDB assigns to the rows in such a table. The row ID is a 6-byte field that increases monotonically as new rows are inserted. Thus, the rows ordered by the row ID are physically in insertion order. Accessing a row through the clustered index is fast because the index search leads directly to the page with all the row data. If a table is large, the clustered index architecture often saves a disk I/O operation when compared to storage organizations that store row data using a different page from the index record. All indexes other than the clustered index are known as secondary indexes. In InnoDB, each record in a secondary index contains the primary key columns for the row, as well as the columns specified for the secondary index. InnoDB uses this primary key value to search for the row in the clustered index.

If the primary key is long, the secondary indexes use more space, so it is advantageous to have a short primary key.


In mysql, if you define int type, e.g. tinyint as tinyint(11), the 11 only means the display width of the integer field.
