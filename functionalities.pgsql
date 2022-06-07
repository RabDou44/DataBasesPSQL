CREATE FUNCTION addFilm( title text,film_time time, director text, year integer,description text) RETURNS void
AS 'INSERT INTO film(tytul,czas,rezyser,rok,opis) VALUES($1,$2,$3,$4,$5)'
LANGUAGE sql;

CREATE FUNCTION dropAllFilm() RETURNS void 
AS 'DELETE FROM film;' 
LANGUAGE sql;

CREATE FUNCTION addRoom(l_miejsc integer) RETURNS void
AS 'INSERT INTO sala(liczba_miejsc) VALUES($1)'
LANGUAGE sql;

CREATE OR REPLACE FUNCTION addUser(uzytkownik text,
                haslo text, 
                staff boolean default false) 
                RETURNS boolean
AS 
$$
DECLARE
        user_added BOOLEAN;
BEGIN
        user_added := FALSE;
        
        IF NOT EXISTS (SELECT 1 FROM uzytkownicy 
            WHERE uzytkownicy.login LIKE uzytkownik AND haslo LIKE haslo AND staff like staff) THEN
            INSERT INTO Uzytkownicy(uzytwnik,haslo,staff) VALUES($1,$2,$3);
            user_added := TRUE;
        END IF;
        
        RETURN user_added;
END;
$$
LANGUAGE plpgsql;

-- for empty cinema has free rooms
-- check if room  is free on specific date and time
CREATE OR REPLACE FUNCTION isRoomFree(t TIMESTAMP, 
                                        req_time TIME,
                                        room INTEGER,
                                        cleaning BOOLEAN) 
                                        RETURNS BOOLEAN
AS $$
DECLARE 
    --clean_time is variable if its required to clean before or after seance
    clean_time TIME := '00:00:00';
    observed_films TABLE(film text, duration TIME, begining TIMESTAMP);
BEGIN 
    
    IF cleaning THEN
        clean_time  = '00:15:00';
    END IF; 


    -- for selected room its checked if there's no available seances
    RETURN NOT EXISTS(SELECT *  FROM seans 
                            WHERE seans.sala = room 
                                AND seans.kiedy BETWEEN t - clean_time AND t + req_time + clean_time );
END;
$$
LANGUAGE plpgsql;

-- add seans
CREATE OR REPLACE FUNCTION addSeans(fname text,
                                    t timestamp, 
                                    room integer,
                                    cleaning BOOLEAN DEFAULT TRUE) 
RETURNS void
AS $$
DECLARE
    -- assure that there titles of movies are unique
    found_film Film%ROWTYPE;
BEGIN    
    -- check if thre 
    SELECT * INTO found_film FROM Film 
                                    WHERE tytul LIKE fname 
                                    ORDER BY rok DESC
                                    LIMIT 1;

    IF ISNULL(found_film) THEN 
        RAISE EXCEPTION 'No film with title: %', $1;
    END IF;

    IF isRoomFree(t, found_film.czas, room, cleaning) THEN
        INSERT INTO Seans VALUES(t,room,found_film.id);
    ELSE
        RAISE EXCEPTION 'Cannot Insert film %', $1;
    END IF;
END;
$$
LANGUAGE plpgsql;


-- buy ticket 
CREATE OR REPLACE FUNCTION printRepertoire() 
RETURNS TABLE (
    title TEXT,
    duration TIME,
    term TIMESTAMP
)
AS 'SELECT tytul,czas,kiedy FROM Seans 
        JOIN Film ON Seans.film_id = Film.id
        WHERE kiedy >= NOW();'
LANGUAGE sql;


