1. В каких городах больше одного аэропорта?

select city "Города, где больше одного аэропорта", count(air) "Количество аэропортов"
from (
	select r.departure_airport air, r.departure_city city
	from bookings.routes r 
	group by 2,1) s
group by city	
having count(air) > 1 

2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?

select departure_airport_name "Аэропорт с рейсами максимальной дальности перелета"
from bookings.routes r 
where (select aircraft_code from bookings.aircrafts order by "range" desc limit 1) = aircraft_code
group by 1 

3. Вывести 10 рейсов с максимальным временем задержки вылета

select f.flight_no "Номер рейса", f.actual_departure::date "Дата вылета",
f.actual_departure::time "Время вылета",
extract (day from (f.actual_departure - f.scheduled_departure)) || ' д. ' ||
extract (hour from (f.actual_departure - f.scheduled_departure)) || ' ч. ' ||
extract (minute from (f.actual_departure - f.scheduled_departure)) || ' мин.' "Время задержки рейса"
from bookings.flights f
where f.scheduled_departure <> f.actual_departure
order by f.actual_departure - f.scheduled_departure desc 
limit 10

4. Были ли брони, по которым не были получены посадочные талоны?

select b.book_ref "Номер бронирования, по которому не получен посадочный талон"
from bookings.bookings b 
join bookings.tickets t on t.book_ref = b.book_ref 
left join bookings.boarding_passes bp on bp.ticket_no = t.ticket_no
where boarding_no is null

5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах в течении дня.

  with cte1 as (
		select s.aircraft_code ,count(s.seat_no) ColFull
		from bookings.seats s
		group by s.aircraft_code),
	cte2 as 	
		(select bp.flight_id, count(bp.seat_no) ColFact
		from bookings.boarding_passes bp
		group by 1
)
select f.flight_no "Номер рейса", f.actual_departure::date "Дата вылета",
f.departure_airport "Аэропорт вылета", cte1.ColFull - cte2.ColFact "Количество свободных мест",
round(((cte1.ColFull - cte2.ColFact)::numeric  / cte1.ColFull)*100, 2) "Процент свободных мест",
sum(cte2.ColFact) over (partition by f.departure_airport, f.actual_departure::date order by f.actual_departure) "Вылетело пассажиров"
from bookings.flights f, cte1, cte2
where cte1.aircraft_code = f.aircraft_code and f.flight_id = cte2.flight_id
order by 2,3,6


6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.

  select p.aircraft_code, round((p.Col/p.ColFull)*100,2) "Процент от общего количества перелетов", p.ColFull "Общее количество перелетов"
  from ( 
  	select distinct f.aircraft_code, count(*) over (partition by f.aircraft_code)::numeric Col, count(*) over ()::numeric ColFull
  	from flights f
  	) as p

7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?

with cte as (
		select f.flight_id, case when tf.fare_conditions = 'Business' then min(tf.amount) end AmountB
		from ticket_flights tf
		join flights f on f.flight_id = tf.flight_id
		group by 1, tf.fare_conditions
		order by 1),
	cte2 as (
		select cte.flight_id , cte.AmountB,	case when tf.fare_conditions = 'Economy' then max(tf.amount) end AmountE
		from cte
		left join ticket_flights tf on tf.flight_id = cte.flight_id and cte.AmountB is not null
		where cte.AmountB is not null
		group by 1,2, tf.fare_conditions
)	
select fv.departure_city "Город вылета", fv.arrival_city "Город прибытия",
	cte2.AmountB "Стоимость перелета Бизнес", cte2.AmountE "Стоимость перелета Эконом"
from cte2
join flights_v fv  on fv.flight_id = cte2.flight_id 
where cte2.AmountB is not null and cte2.AmountE is not null
group by 1,2,3,4
having cte2.AmountB < cte2.AmountE

8. Между какими городами нет прямых рейсов?

Создание представления:

create materialized view flights_v2 as 
	select a.city "DepCity", a2.city "ArrCity"
	from flights f
	join airports a on a.airport_code = f.departure_airport
	join airports a2 on a2.airport_code = f.arrival_airport
	group by 1,2
with data;

Запрос:

	select distinct a.city "DepCity", a2.city "noArrCity"
	from airports a, airports a2 
	where a.city != a2.city
	group by 1,2 
	except 
	select distinct fv."DepCity" , fv2."ArrCity" 
	from flights_v2 fv, flights_v2 fv2 
	where fv2."DepCity" = fv."DepCity" and fv."ArrCity" = fv2."ArrCity"
	order by 1,2

9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы 

 select a.city "Город вылета", a2.city "Город прибытия", a3.model "Модель самолета", a3."range" "Дальность полета самолета",
 	Round(acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*
 	cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371) "Расстояние между городами",
 	case when (a3."range" - Round(acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*
 		cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371)) > 100 
 		then 'Да' 
 		else 'Нет' end "Применимость самолета на маршруте"
 from flights f
 join airports a  on a.airport_code = f.departure_airport 
 join airports a2  on a2.airport_code = f.arrival_airport 
 join aircrafts a3 on a3.aircraft_code = f.aircraft_code 
 group by 1,2,3,4,5,6
 order by 1,2
