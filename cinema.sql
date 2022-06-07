-- Created by Vertabelo (http://vertabelo.com)
-- Last modification date: 2022-05-23 21:55:12.708

-- tables
-- Table: Film
CREATE TABLE Film (
    tytul text  NOT NULL,
    czas time  NOT NULL,
    rezyser text  NOT NULL,
    rok int  NOT NULL,
    opis text  NOT NULL,
    id serial  NOT NULL,
    CONSTRAINT Film_pk PRIMARY KEY (id)
);

-- Table: Sala
CREATE TABLE Sala (
    nr serial  NOT NULL,
    liczba_miejsc int  NOT NULL,
    CONSTRAINT Sala_pk PRIMARY KEY (nr)
);

-- Table: Seans
CREATE TABLE Seans (
    kiedy timestamp  NOT NULL,
    nr_sali serial  NOT NULL,
    Film_Id serial  NOT NULL,
    id serial  NOT NULL,
    CONSTRAINT Seans_pk PRIMARY KEY (id)
);

-- Table: Uzytkownicy
CREATE TABLE Uzytkownicy (
    login text  NOT NULL,
    haslo text  NOT NULL,
    staff boolean  NOT NULL,
    id serial  NOT NULL,
    CONSTRAINT Uzytkownicy_pk PRIMARY KEY (id)
);

-- Table: koszyk
CREATE TABLE koszyk (
    id_klienta serial  NOT NULL,
    id_seans serial  NOT NULL
);

-- foreign keys
-- Reference: Seans_Film (table: Seans)
ALTER TABLE Seans ADD CONSTRAINT Seans_Film
    FOREIGN KEY (Film_Id)
    REFERENCES Film (id)  
    NOT DEFERRABLE 
    INITIALLY IMMEDIATE
;

-- Reference: Seans_Sala (table: Seans)
ALTER TABLE Seans ADD CONSTRAINT Seans_Sala
    FOREIGN KEY (nr_sali)
    REFERENCES Sala (nr)  
    NOT DEFERRABLE 
    INITIALLY IMMEDIATE
;

-- Reference: koszyk_Klient (table: koszyk)
ALTER TABLE koszyk ADD CONSTRAINT koszyk_Klient
    FOREIGN KEY (id_klienta)
    REFERENCES Uzytkownicy (id)  
    NOT DEFERRABLE 
    INITIALLY IMMEDIATE
;

-- Reference: koszyk_Seans (table: koszyk)
ALTER TABLE koszyk ADD CONSTRAINT koszyk_Seans
    FOREIGN KEY (id_seans)
    REFERENCES Seans (id)  
    NOT DEFERRABLE 
    INITIALLY IMMEDIATE
;

-- End of file.

