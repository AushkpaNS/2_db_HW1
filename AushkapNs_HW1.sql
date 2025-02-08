-- Создаём таблицы для оригинальных таблиц и импортируем в них данные средствами импорта DBeaver
create table transaction_orig (transaction_id int
							, product_id int
							, customer_id int
							, transaction_date date
							, online_order boolean
							, order_status varchar(16)
							, brand varchar(128)
							, product_line varchar(16)
							, product_class	varchar(16)
							, product_size varchar(16)
							, list_price numeric(16, 2)
							, standard_cost numeric(16, 2)
)

create table customer_orig (customer_id int
						, first_name varchar(64)
						, last_name	varchar(64)
						, gender varchar(64)
						, DOB date
						, job_title	varchar(128)
						, job_industry_category	varchar(128)
						, wealth_segment varchar(64)
						, deceased_indicator varchar(4)
						, owns_car varchar(4)
						, address varchar(512)
						, postcode varchar(32) -- хотя по данным кажется, что это число, но, вообще говоря, почтовый индекс может быть буквами и первый ноль тоже значим
						, state	varchar(64)
						, country varchar(128)
						, property_valuation int

)

-- Проверим, что таблицы заполнены и количсество записей совпадает с количеством в первоначальном файле:
select * from transaction_orig
select * from customer_orig
select count(*) from transaction_orig -- 20000
select count(*) from customer_orig -- 4000

-- Поиск дубликатов
-- сразу проверим по id
select COUNT(distinct transaction_id) from transaction_orig -- совпало с исходным количеством, то есть дубликатов по id транзакции нет
select count(distinct customer_id) from customer_orig -- совпало с исходным количеством, то есть дубликатов по id клиентов нет
-- То есть в таблицах полных дубликатов нет.

-- Проанализируем нормализованы ли эти таблицы.
-- 1. customer_orig. 
--   Составных полей нет, кроме, быть может address, но для адреса на практике это допустимо. Поэтому, с учётом того, что дубликатов нет, таблица находятся в 1НФ.
--   customer_id является простым первичным ключом.
--   *Теоретически, при желании, можно было бы поискать еще один потенциальный ключ как сочетание имени, фамилии, даты рождения и, может быть, данных адреса.
--   *но это не лучший вариант на практике из-за частой проблемы дублей карточек клиентов (клиент физически один, но сущности и соответственно ссылки на эти сущности в других таблицах разные). Поэтому так делать не будем.
--   Поэтому таблица находится в 2НФ.
--   Далее, например, логически address, state и country определяют postcode, таким образом, есть транзитивная зависимость.
--   То есть с этой точки зрения логики таблица не находится в 3НФ.
--   Однако, вопреки логике, мы видим, что в таблице для одного и того же набора address, state и country есть разные значения postcode
select * from customer_orig co1 
inner join customer_orig co2 
on co1.address = co2.address and co1.country = co2.country and co1.state = co2.state
and co1.postcode != co2.postcode
--   Поэтому, если считать, что в данных нет ошибки, то таблица находится в 3НФ
-- 2. transactions_orig.
--   Составных полей нет, дубликатов нет, поэтому таблица находятся в 1НФ.
--   transaction_id является простым первичным ключом.
--   *Опять же, если не фантазировать, что в одной дате один клиент не может совершить более одной транзакции и т.п, то потенциальных ключей логически больше нет.
--   Поэтому таблица находится в 2НФ.
--   Далее, если подходить к вопросу с точки зрения бизнес-логики, то данные о продукте (brand, product_line, product_class, product_size)
--   должны были бы однозначно зависеть от product_id.
--   В этом случае появляется транзитивная зависимость и таблица не находитя в 3НФ.
--   Однако мы видим, что в таблице для одних и тех же значений product_id могут отличаться значения brand и т.д. Например: 
select * from transaction_orig where product_id = 67
--   Поэтому, если считать, что в данных нет ошибки и дополнительно считать, что list_price и standart_cost так же не зависят однозначно от продукта и друг от друга, то транзитивных зависисмостей нет
--   И тогда таблица находилась бы в 3НФ.

-- Создаём нормализованную базу данных.
-- Строго говоря, без описания бизнес-логики полей нельзя гарантированно спроектировать нормализованную БД.
-- Поэтому буду отталкиваться от следующих предположений:
--   1. Разные значения данных продукта для одинаковых product_id - это ошибка в данных, учитывая, 
--      что судя по данным, речь везде идёт о велосипедах и product_id нелья интерпретировать как "тип продукта" (пылесос, автомобиль и т.п.) и это больше похоже на "модель".
select distinct product_id, brand, product_line, product_class, product_size from transaction_orig order by product_id, brand, product_line, product_class, product_size
--   2. list_price и standart_cost логически относятся к транзакции, а не к продукту. И не зависят друг от друга (хотя standart_cost возможно относится к продукту. На практике я бы это уточнял у бизнес-заказчика)
--   3. Считаем, что brand, product_line, product_class, product_size также не зависят друг от друга.
--   4. Видим, что все адреса в таблице customer_orig уникальны и для одного и того же набора address, state и country есть разные значения postcode.
--      Но всё же выведем адреса в отдельную таблицу. Это на практике уменьшило бы объем занимаемой памяти, так как на один и тот же адрес может быть много заказов.
--      *например, часто стараются поддерживать КЛАДР, в этом случае есть несколько справочников с данными из КЛАДР, ссылки на записи из КЛАДР 
--      *и адрес отдельно, если в КЛАДР адрес не найден.
--   5. В таблице transaction_orig есть один customer_id, которого нет в customer_orig (5034).
select distinct customer_id from transaction_orig
except
select distinct customer_id from customer_orig
--      Чтобы не нарушать ограничение целостности добавим этого клиента в таблицу customers с неопределёнными данными
--      И добавим в таблицу addresses запись с неопределённым адресом

-- Найдём пустые значения в колонках 
-- Начало поиска колонок с пустыми значениями ->
select distinct 'transaction_orig' as table_name, 'transaction_id' as column_name from transaction_orig where transaction_id is null
union all
select distinct 'transaction_orig', 'product_id' from transaction_orig where product_id is null
union all
select distinct 'transaction_orig', 'customer_id' from transaction_orig where customer_id is null
union all
select distinct 'transaction_orig', 'transaction_date' from transaction_orig where transaction_date is null
union all
select distinct 'transaction_orig', 'online_order' from transaction_orig where online_order is null
union all
select distinct 'transaction_orig', 'order_status' from transaction_orig where order_status is null or order_status = ''
union all
select distinct 'transaction_orig', 'brand' from transaction_orig where brand is null or brand = ''
union all
select distinct 'transaction_orig', 'product_line' from transaction_orig where product_line is null or product_line = ''
union all
select distinct 'transaction_orig', 'product_class' from transaction_orig where product_class is null or product_class = ''
union all
select distinct 'transaction_orig', 'product_size' from transaction_orig where product_size is null or product_size = ''
union all
select distinct 'transaction_orig', 'list_price' from transaction_orig where list_price is null
union all
select distinct 'transaction_orig', 'standard_cost' from transaction_orig where standard_cost is null
union all
-- customer_orig
select distinct 'customer_orig' as table_name, 'customer_id' as column_name from customer_orig where customer_id is null
union all
select distinct 'customer_orig', 'first_name' from customer_orig where first_name is null or first_name = ''
union all
select distinct 'customer_orig', 'last_name' from customer_orig where last_name is null or last_name = ''
union all
select distinct 'customer_orig', 'gender' from customer_orig where gender is null or gender = ''
union all
select distinct 'customer_orig', 'dob' from customer_orig where dob is null
union all
select distinct 'customer_orig', 'job_title' from customer_orig where job_title is null or job_title = ''
union all
select distinct 'customer_orig', 'job_industry_category' from customer_orig where job_industry_category is null or job_industry_category = ''
union all
select distinct 'customer_orig', 'wealth_segment' from customer_orig where wealth_segment is null or wealth_segment = ''
union all
select distinct 'customer_orig', 'deceased_indicator' from customer_orig where deceased_indicator is null or deceased_indicator = ''
union all
select distinct 'customer_orig', 'owns_car' from customer_orig where owns_car is null or owns_car = ''
union all
select distinct 'customer_orig', 'address' from customer_orig where address is null or address = ''
union all
select distinct 'customer_orig', 'postcode' from customer_orig where postcode is null or postcode = ''
union all
select distinct 'customer_orig', 'state' from customer_orig where state is null or state = ''
union all
select distinct 'customer_orig', 'country' from customer_orig where country is null or country = ''
union all
select distinct 'customer_orig', 'property_valuation' from customer_orig where property_valuation is null
-- <- Конец поиска колонок с пустыми значениями

-- В результате получили колонки с пустыми значениями:
--transaction_orig	brand
--transaction_orig	product_line
--transaction_orig	product_class
--transaction_orig	product_size
--transaction_orig	standard_cost
--customer_orig		DOB
--customer_orig		last_name
--customer_orig		job_title
-- Еще в колонке customer_orig.job_industry_category есть значения n/a, поэтому на всякий случай сделаем допустимым пустое значение для неё тоже

-- Из-за поблемы с не уникальностью product_id для разных брендов и т.д. Переопределим product_id на уникальный.
-- И создадим таблицу соответствия новых product_id старым значениям, чтобы не потерять информацию. 

-- Создаём таблицы:
create table transactions (
  transaction_id int primary key,
  product_id int not null,
  customer_id int not null,
  transaction_date date not null,
  online_order boolean not null,
  order_status varchar(16) not null,
  list_price numeric(16,2) not null,
  standard_cost numeric(16,2)
);

create table products (
  product_id int primary key,
  brand varchar(128),
  product_line varchar(16),
  product_class varchar(16),
  product_size varchar(16)
);

create table products_id_corr (
  product_id int primary key,
  product_id_old int not null
);

create table customers (
  customer_id int primary key,
  first_name varchar(64) not null,
  last_name varchar(64),
  gender varchar(64) not null,
  DOB date,
  job_title varchar(128),
  job_industry_category varchar(128),
  wealth_segment varchar(64) not null,
  deceased_indicator boolean not null,
  owns_car boolean not null,
  address_id int not null,
  property_valuation int not null
);

create table addresses (
  address_id int primary key,
  address varchar(512) not null,
  postcode varchar(32) not null,
  state varchar(64) not null,
  country varchar(128) not null
);

-- Задаём связи:
alter table transactions ADD FOREIGN KEY (product_id) REFERENCES products (product_id);

alter table products ADD FOREIGN KEY (product_id) REFERENCES products_id_corr (product_id);

alter table transactions ADD FOREIGN KEY (customer_id) REFERENCES customers (customer_id);

alter table customers ADD FOREIGN KEY (address_id) REFERENCES addresses (address_id);

-- Заполним таблицы данными.
-- Для этого сначала добавим столбец product_id_new в таблицу transaction_orig 
-- и заполним её новыми уникальными значениями product_id, где уникальность product_id определяется уникальностью набора [product_id, brand, product_line, product_class, product_size].
-- И добавим столбец address_id в таблицу customer_orig и заполним её новыми уникальными значениями
alter table transaction_orig add column product_id_new INT not null default 0;

update transaction_orig
   set product_id_new = subq.row_num 
   from (
       select product_id, brand, product_line, product_class, product_size, ROW_NUMBER() over () as row_num from (
			select distinct product_id, brand, product_line, product_class, product_size from transaction_orig
			)
   		) as subq
   where transaction_orig.product_id = subq.product_id 
   		and transaction_orig.brand = subq.brand 
   		and transaction_orig.product_line = subq.product_line 
   		and transaction_orig.product_class = subq.product_class 
   		and transaction_orig.product_size = subq.product_size
   		
alter table customer_orig add column address_id INT not null default 0;

update customer_orig
   set address_id = subq.row_num 
   from (
       select address, postcode, state, country, ROW_NUMBER() over () as row_num from (
			select distinct address, postcode, state, country from customer_orig
			)
   		) as subq
   where customer_orig.address = subq.address 
   		and customer_orig.postcode = subq.postcode 
   		and customer_orig.state = subq.state 
   		and customer_orig.country = subq.country
   		
-- Заполним таблицу соответствия старых и новых product_id
insert into products_id_corr (product_id, product_id_old)
   select distinct product_id_new, product_id
   from transaction_orig;

-- Заполним таблицу продуктов
insert into products (product_id, brand, product_line, product_class, product_size)
   select distinct product_id_new, brand, product_line, product_class, product_size
   from transaction_orig;  		
   		
-- Заполним таблицу адресов
insert into addresses (address_id, address, postcode, state, country)
   select address_id, address, postcode, state, country
   from customer_orig;

-- Заполним таблицу клиентов
insert into customers (customer_id, first_name, last_name, gender, DOB, job_title, job_industry_category, wealth_segment, deceased_indicator, owns_car, address_id, property_valuation)
   select customer_id, first_name, last_name, gender, DOB, job_title, job_industry_category, wealth_segment, deceased_indicator = 'Y', owns_car = 'Yes', address_id, property_valuation
   from customer_orig;

-- Заполним таблицу транзакций
-- Из-за проблемы клиента, которого нет в таблице customers (см. выше) добавим неопределённый адрес и неопределённого клиента
insert into addresses (address_id, address, postcode, state, country)
   values (-1, 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN');

insert into customers (customer_id, first_name, last_name, gender, DOB, job_title, job_industry_category, wealth_segment, deceased_indicator, owns_car, address_id, property_valuation)
	values (5034, 'UNKNOWN', '', 'UNKNOWN', '0001-01-01', '', '', 'UNKNOWN', FALSE, FALSE, -1, -1);

insert into transactions (transaction_id, product_id, customer_id, transaction_date, online_order, order_status, list_price, standard_cost)
   select transaction_id, product_id_new, customer_id, transaction_date, online_order, order_status, list_price, standard_cost
   from transaction_orig;

-- Посмотрим результат:
select count(*) from transactions -- 20000
select count(*) from customers -- 4001 на одного больше, так как добавили неизвестного клиента c customer_id 5034
select count(*) from products -- 190 уникальных продуктов
select count(*) from products_id_corr -- 190 соответствий старых и новых product_id
select count(distinct product_id) from transaction_orig -- 101 - было меньше уникальных product_id, но была проблема разных значений [brand, product_line, product_class, product_size] для одного значения product_id
select count(*) from addresses -- 4001 уникальный адрес, включая неопределённый адрес

select * from transactions
select * from customers
select * from products
select * from products_id_corr
select * from addresses


