-----------------------------------------------FILM------------------------------------------------------------
-- adding
-- editing description
-- ...

-- DROP FUNCTION IF EXISTS addFilm(text, time, text, integer,text);
CREATE OR REPLACE FUNCTION addFilm(title text, duration interval, director text, prod_year integer, description text DEFAULT '') 
RETURNS boolean
AS
$$
DECLARE
    film_added boolean := FALSE;
BEGIN
    IF NOT EXISTS( SELECT 1 FROM Film WHERE Film.tytul LIKE title) THEN 
        INSERT INTO film(tytul,czas,rezyser,rok,opis) VALUES($1,$2,$3,$4,$5);
            film_added := TRUE;
    END IF;
    RETURN film_added;
END;
$$ 
LANGUAGE plpgsql;

-- DROP FUNCTION IF EXISTS dropAllFilm();
CREATE FUNCTION dropAllFilm() RETURNS void 
AS 'DELETE FROM film;' 
LANGUAGE sql;

CREATE OR REPLACE FUNCTION  addDescription(film_id integer,new_desc text) 
RETURNS void 
AS
$$
BEGIN
    UPDATE FILM 
    SET opis = new_desc 
    WHERE id = film_id;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------ROOM-------------------------------------------------------------
-- adding Room
-- is specfic room free
-- return table of free rooms for given timestamp: 
-- printROOM unnceseccary
-- get reservations

DROP FUNCTION addroom(integer);
CREATE OR REPLACE FUNCTION addRoom(seats_num integer) RETURNS void
AS 
'INSERT INTO sala(liczba_miejsc) VALUES($1)'
LANGUAGE sql;


CREATE OR REPLACE FUNCTION isRoomAvailable( room integer,
                                        t TIMESTAMP,
                                        req_time INTERVAL default '03:00:00',
                                        cleaning BOOLEAN default TRUE) 
                                        RETURNS BOOLEAN
AS $$
DECLARE 
    --clean_time is variable if its required to clean before or after seance
    clean_time INTERVAL := '00:00:00';
BEGIN 
    IF cleaning THEN
        clean_time  = '00:15:00';
    END IF; 

    RETURN EXISTS (SELECT * 
                FROM freerooms(t - clean_time, req_time + 2*clean_time) AS f
                WHERE room = f.nr_room);
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION freeRooms(t TIMESTAMP default NOW(), 
                                    duration INTERVAL default '03:00:00')
    RETURNS TABLE(nr_room INT, nr_seat INT)
AS  $$
BEGIN  
    RETURN QUERY SELECT nr, liczba_miejsc FROM Sala  
            LEFT OUTER JOIN (SELECT * FROM filmsoccupyingrooms(t,duration)) AS f
                        ON f.room = Sala.nr
                        WHERE film_id IS NULL
                        ORDER BY nr;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No free rooms between % and %', $1, ($1 + $2);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION filmsOccupyingRooms(t TIMESTAMP default NOW(), 
                                    duration INTERVAL default '24:00:00')
    RETURNS TABLE( film_id INT, room INT)
AS  $$
BEGIN  
    RETURN QUERY SELECT Film.id, nr_sali FROM film 
                            JOIN Seans ON Seans.film_id = Film.id 
                            WHERE NOT ( kiedy >  t + duration OR  (kiedy + czas) < t)
                            ORDER BY kiedy, nr_sali;

END;
$$ LANGUAGE plpgsql;
-----------------------------------------------SEANCE----------------------------------------------------------
-- addSeance    
-- places for seance
-- placesLeft
CREATE OR REPLACE FUNCTION addSeans(f_id integer,
                                    t timestamp, 
                                    room integer DEFAULT 0,
                                    cleaning Boolean DEFAULT TRUE ) 
RETURNS BOOLEAN
AS $$
DECLARE 
    req_time INTERVAL;
    res BOOLEAN := FALSE;
BEGIN   
    IF NOT EXISTS (SELECT 1 FROM FILM WHERE Film.id = f_id) THEN 
        RAISE EXCEPTION 'No film with id: %', $1;
    ELSE
        SELECT czas INTO req_time 
        FROM Film 
        WHERE Film.id = f_id 
        LIMIT 1; 
    END IF;
    
    IF isRoomAvailable(room,t,req_time,cleaning) THEN
        INSERT INTO Seans VALUES(t,room,f_id);
        res := TRUE;
    ELSE
        RAISE EXCEPTION 'Room % is not available for specific time', $1;
    END IF;
    RETURN res;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION availableSeats(seans_id INT)
RETURNS INT
AS  
$$
DECLARE
    all_seats INT = 0;  
    occupied_seats INT = 0; 
BEGIN
    SELECT liczba_miejsc INTO all_seats FROM Sala 
                    JOIN Seans ON Seans.nr_sali = Sala.nr 
                    WHERE Seans.id = seans_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No such room  %', $1;
    END IF;

    SELECT COUNT (*) INTO occupied_seats FROM Seans 
                            JOIN koszyk ON koszyk.id_seans = seans.id
                            WHERE seans_id = seans.id;
    
    RETURN all_seats - occupied_seats;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getReservation(user_id INT)
RETURNS TABLE( title TEXT, 
                seance_time TIMESTAMP,
                seans_id INT,
                places  INT)
AS  
$$
BEGIN
    RETURN QUERY SELECT tytul title, kiedy seance_time, p.id seans_id, ile places FROM Film 
                JOIN (SELECT film_id, kiedy , id, ile  
                    FROM Seans JOIN Koszyk ON Koszyk.id_seans = Seans.id
                    WHERE id_klienta = user_id) p 
                ON Film.id = p.film_id;

END;
$$ LANGUAGE plpgsql;

-----------------------------------------------CINEMA OFFER----------------------------------------------------------
-- print repertoire for selected week ('next' by default) (specific movie if selected if not then all)
-- basic repertoire
CREATE OR REPLACE FUNCTION repertoire1( t DATE DEFAULT NOW(), w INT DEFAULT 0) 
RETURNS TABLE (
    title TEXT,
    duration TIME,
    seance_time TIMESTAMP,
    overwiew TEXT,
    room INT
)
AS

$$
DECLARE
    curr_day INTEGER := EXTRACT(dow FROM t);
    next_sunday TIMESTAMP := t::date + (6 - curr_day) + w*7 + '23:59:59'::time;
BEGIN
    RETURN QUERY SELECT tytul, czas, kiedy, opis, nr_sali
        FROM Seans
        JOIN Film ON Seans.film_id = Film.id 
        WHERE kiedy BETWEEN ( NOW()::timestamp - '02:00:00'::interval) AND next_sunday
        ORDER BY kiedy; 
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION repertoire2( t DATE DEFAULT NOW(), w INT DEFAULT 0) 
RETURNS TABLE (
    title TEXT,
    duration TIME,
    seance_time TIMESTAMP,
    overwiew TEXT,
    room INT,
    id INT,
    tickets INT
)
AS
$$
DECLARE
    curr_day INTEGER := EXTRACT(dow FROM t);
    next_sunday TIMESTAMP := t::date + (6 - curr_day) + w*7 + '23:59:59'::time;
BEGIN
    RETURN QUERY SELECT tytul, czas, kiedy, opis, nr_sali, MS.id, bilety::INT
        FROM ( SELECT Seans.id, kiedy, nr_sali, film_id, COALESCE (SUM(Koszyk.ile),0) bilety
                FROM Seans LEFT JOIN Koszyk ON Seans.id=koszyk.id_seans 
                GROUP BY Seans.id) as MS
        JOIN Film ON MS.film_id = Film.id 
        WHERE kiedy BETWEEN ( NOW()::timestamp - '02:00:00'::interval)::date AND next_sunday
        ORDER BY kiedy; 
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION repertoire3( t DATE DEFAULT NOW(), w INT DEFAULT 0) 
RETURNS TABLE (
    title TEXT,
    duration TIME,
    seance_time TIMESTAMP,
    id INT,
    available_seats INT
)
AS
$$
BEGIN
    RETURN QUERY SELECT R.title, R.duration, R.seance_time, R.id, liczba_miejsc - R.tickets
        FROM repertoire2(t,w) as R
        JOIN Sala ON Sala.nr = R.room; 
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION clearRepertoire( t DATE DEFAULT NOW()) 
RETURNS void
AS
$$
BEGIN
    DELETE FROM Seans
    WHERE kiedy >= t;
END;
$$ LANGUAGE plpgsql;


-----------------------------------------------USER------------------------------------------------------------
-- addUser
-- print cart
-- modify cart
-- drop past movies from cart (till 15 minutes before ending of Seance)
CREATE OR REPLACE FUNCTION addUser(username text,
                password1 text, 
                isstaff boolean default false) 
RETURNS boolean
AS 
$$
DECLARE
        user_added BOOLEAN := FALSE;
BEGIN
        IF NOT EXISTS (SELECT * FROM uzytkownicy 
            WHERE uzytkownicy.login LIKE username AND uzytkownicy.haslo LIKE password1 AND uzytkownicy.staff = isstaff) THEN
            INSERT INTO Uzytkownicy(login,haslo,staff) VALUES($1,$2,$3);
            user_added := TRUE;
        END IF;
        
        RETURN user_added;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION deleteUser(username TEXT)
RETURNS BOOLEAN
AS 
$$
DECLARE 
    res boolean := FALSE;
BEGIN
    IF EXISTS( SELECT * FROM uzytkownicy WHERE login LIKE username) THEN
        DELETE FROM Uzytkownicy
        WHERE username LIKE login;
        res := TRUE;
    END IF;

    RETURN res;
END;
$$ 
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION addSeansToKart(user_id integer, seans_id integer, howmany integer DEFAULT 1)
RETURNS boolean
AS
$$
DECLARE
    seats INT := 0 ;
BEGIN
    IF howmany < 1 THEN 
        RAISE EXCEPTION 'value_error';
    END IF; 

    SELECT * INTO seats FROM howManySeats(seans_id);
    IF seats - howmany >= 0 THEN
        INSERT INTO koszyk VALUES($1, $2, $3);
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END;
$$ Language plpgsql;


-------------------------------------------------- Statistics--------------------------------------
CREATE OR REPLACE FUNCTION howManySeats(s integer)
RETURNS INTEGER
AS
$$
DECLARE
    seance_seats integer = 0; 
    taken integer = 0;
BEGIN
    SELECT liczba_miejsc INTO seance_seats FROM Seans 
                                JOIN Sala ON Seans.nr_sali = Sala.nr 
                                WHERE Seans.id = s;
    
    IF seance_seats ISNULL THEN
        RETURN 0;
    END IF;

    SELECT SUM(ile) INTO taken FROM Seans 
        JOIN koszyk ON Seans.id  = koszyk.id_seans
        WHERE koszyk.id_seans = s;    

    IF taken ISNULL THEN
        RETURN seance_seats;
    END if;

    RETURN seance_seats - taken;
END;
$$ Language plpgsql;    