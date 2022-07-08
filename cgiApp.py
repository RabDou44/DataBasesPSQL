#!/usr/bin/python
from decimal import ROUND_CEILING
from matplotlib.style import use
import sys
import os
import psycopg2
import typing
import pandas as pd
from configparser import ConfigParser
from IPython.display import HTML
from datetime import datetime
import pandas as pd

NOW = datetime.now().strftime("%Y-%m-%d %H:%M")
DEF_TIME = '03:00:00'
DEF_SEATS = 50

"""
It's scirpt designed for reservation of Seances in cinema.
Console run with 'python cgiApp.py' will automatically initiate application
Module consist of function divided in following categories:
- general config
- database functions e.g.: config(filname, section), connect()
- user function e.g.: createUser( *args)
- Repertoire and Film functions.: 
- Seance functions e.g.: addSeance
- others

"""

### General config, reset

def resetApp(deep = False):
    """
        Deletes all user except (superadmin, admin) 
        Deletes all Carts/Koszyk
        Delete all Seances/Seanse
        Sala/Room and Film remains untouched 
    """
    pass

### Database functions

def config(filname = 'db.ini',section ='postgresql'):
    parser = ConfigParser()
    file = open(filname)
    parser.read_file(file)

    db_params={}
    if parser.has_section(section):
        params = parser.items(section) 
        for x in params:
            db_params[x[0]] = x[1]
    else:
        raise Exception(f'Section {section} not found in file {filname}')
    
    return db_params

def connect():
    '''
        creates connection with db configured in config(* args)
    '''
    conn = None
    try:
        params = config()
        # print("Loading ...")
        conn = psycopg2.connect(**params)
        return conn

    except (Exception, psycopg2.DatabaseError) as error:
        print(error)
        print("Cannot connect with database!")
        sys.exit()
    # finally:
    #     if conn is None:
    #         conn.close()
    #         print('Database connection close')


### user & admins functions

def exitApp():
    res = input("Do you want to exit app [y/n]?")
    if res == "Y" or res == "y":
        sys.exit()

def createUser(user_name,password,staff = False):
    conn = connect()
    curr = conn.cursor()
    res = True
    if not ( isUser(user_name,password) or isAdmin(user_name,password) ):
        curr.execute("INSERT INTO Uzytkownicy(login, haslo, staff) Values('%s','%s',%r)"% (user_name,password,staff))
        conn.commit()
    else:
        print("[%s %s staff:%r] already exists]"%(user_name, password, staff))
        res = False
    return res

def isUser(user_name,password, staff=False):
    curr = connect().cursor()
    curr.execute("""SELECT 1 FROM Uzytkownicy 
                    WHERE login LIKE '%s' 
                    AND haslo LIKE '%s' 
                    AND staff = %r;"""% (user_name, password, staff))

    return not (curr.fetchone() is None)

def isAdmin(user_name, password):
    return isUser(user_name, password, True)


def getUserId(user_name: str, password: str) -> int:
    if isAdmin(user_name, password) != isUser(user_name,password):
        curr = connect().cursor()
        curr.execute("""SELECT id FROM Uzytkownicy 
                        WHERE login LIKE '%s' 
                        AND haslo LIKE '%s';"""%(user_name, password) )
        row = curr.fetchone()
        return row[0]
    return None

def getReservation(user_id: int) -> pd.DataFrame:
    conn = connect()
    curr = conn.cursor()
    curr.execute("""SELECT * FROM getReservation(%d);""" % user_id )
    reservation = pd.DataFrame(curr.fetchall())
    if not reservation.empty:
        reservation.columns = [x[0] for x in curr.description]
    conn.close()
    return reservation if not reservation.empty else None
    

### Repertoire and Film functions

def getFilmBase():
    conn = connect()
    curr = conn.cursor()
    curr.execute("SELECT * FROM Film;")
    filmBase = pd.DataFrame(curr.fetchall())
    conn.close()
    if not filmBase.empty:
        filmBase.columns = [x[0] for x in curr.description]
        # filmBase = filmBase.append({'Flaga': '*'},ignore_index=True)
    return filmBase if not filmBase.empty else None

def getRepertoire(date = NOW, mode=1)-> pd.DataFrame:
    conn = connect()
    curr = conn.cursor()
    rep = "repertoire"+ str(mode)
    curr.execute("SELECT * FROM %s('%s')" % (rep,date))
    repertoire = pd.DataFrame(curr.fetchall())
    if not repertoire.empty:
        repertoire.columns = [x[0] for x in curr.description]
    conn.close()
    return repertoire if not repertoire.empty else None

def getFilmId(film: str) -> int:
    conn = connect()
    curr = conn.cursor()
    curr.execute("SELECT id FROM Film WHERE Film.tytul LIKE '%s' ;"% film)
    x = curr.fetchone()
     
    return x[0] if (x is not None) else None

def getFilmDuration(f_id) -> str:
    conn = connect()
    curr = conn.cursor()
    curr.execute("SELECT czas FROM Film WHERE id = %d;"% f_id)
    time = curr.fetchone()
    conn.close()
    return time[0]

def getRoomForFilm(f_id: int, date = NOW, seats = DEF_SEATS):
    conn = connect()
    curr = conn.cursor()
    film_dur = getFilmDuration(f_id)
    film_dur = "00:00:00" if film_dur is None else film_dur
    

    curr.execute("""SELECT nr_room FROM freerooms('%s','%s')
                    WHERE nr_seat >=  %d 
                    ORDER BY nr_seat 
                ; """ %(date,film_dur,seats))
    free_room = curr.fetchone()

    conn.close()
    if free_room is None:
        print("[There is no free room for (%d, %s, %d) ]"%(f_id, date,))

    return free_room[0] if (free_room is not None) else None

def filmExits(title, director, year):
    conn = connect()
    curr = conn.cursor()
    curr.execute("""SELECT 1 FROM Film
                    WHERE tytul LIKE '%s' 
                        AND rezyser LIKE '%s' 
                        AND  rok = '%d';"""%(title,director,year))
    res = curr.fetchone()
    conn.close()
    return res is not None

def addFilm(title, duration,director, year, overview) -> bool:
    if not filmExits(title, director, year):
        conn = connect()
        curr = conn.cursor()
        curr.execute(""" INSERT INTO Film(tytul, czas, rezyser, rok, opis) 
                        Values('%s','%s','%s', %d, '%s' )"""%(title, duration, year, overview))
        conn.commit()
        conn.close()
        return filmExits(title, director, year)
    else:
        return False    

### Seance functions 

def seanceExists(film_title, date):
    conn = connect()
    curr = conn.cursor()
    film_id = getFilmId(film_title)
    if film_id is not None:
        curr.execute("""SELECT 1 FROM Seans 
                        WHERE film_id = %d AND 
                        kiedy = '%s' """%(film_id, date))
    return False

def addSeance(film, date, where = 0, cleaning = True):

    conn = connect()
    curr = conn.cursor()
    id = getFilmId(film) if type(film) == str else film
    where = getRoomForFilm(film,date) if (where == 0) else where 
    if (id is not None) and (where is not None):
        try:
            curr.execute("SELECT addSeans(%d,'%s',%d, %r);" %(id, date.__str__(), where, cleaning))
            conn.commit()
            input()
        except Exception as error:
            print ("Exception TYPE:", type(error))
            print ("Seance for %s on %s  in %d cannot be added"%(film, date.__str__(), where))
    conn.close()

def addSeance2(film_id: int, date, where = None, cleaning = True) -> bool:

    conn = connect()
    curr = conn.cursor()
    where = getRoomForFilm(film_id,date) if (where is None) else where 

    if (id is not None) and (where is not None):
        try:
            curr.execute("SELECT addSeans(%d,'%s',%d, %r);" %(film_id, date.__str__(), where, cleaning))
            conn.commit()
        except Exception as error:
            print ("Exception TYPE:", type(error))
            print ("Seance for %s on %s  in %d cannot be added"%(film_id, date.__str__(), where))
    conn.close()


def addSeanceToCart(client_id, seance_id, tickets=1): 
    conn = connect()
    curr = conn.cursor()
    curr.execute("""SELECT addSeansToKart(%d,%d,%d);
                """%(client_id,seance_id,tickets))
    conn.commit()
    res = curr.fetchone()
    conn.close()

    return res[0]

def availableSeats(seance_id):
    conn = connect()
    curr = conn.cursor()
    curr.execute(""" SELECT availableSeats(%d)"""%(seance_id))
    res = curr.fetchone()
    conn.close()
    return res[0] if res is not None else None

def cancelReservation(client_id: int, r_id: int):
    """
        client_id - integer referring to specific client
        r_id - reservation id referring to seance bought by client
    """
    conn = connect()
    curr = conn.cursor()
    curr.execute("DELETE FROM Koszyk WHERE id_klienta = %d AND id_seans = %d;" % (client_id, r_id))
    conn.commit()
    conn.close()


def clearRepertoire(t = NOW):
    conn = connect()
    curr = conn.cursor()
    curr.execute("SELECT clearRepertoire('%s')"%t)
    conn.commit()
    conn.close()

# interface functions 
    

def mainView(opt = "", output = ""):
    os.system('CLS')
    print("""
    ---------------------------------------------
    |                  SUPER CINEMA             |
    ---------------------------------------------
    """)
    print(output)
    print("""
    ---------------------------------------------""")
    print(opt,"""
    [e] exit
    ---------------------------------------------
    """)


def chooseOptionPanel(*params, action):
    """
        params = (opt, output)
    """

    pass

def serviceLoop(user) -> None:
    user_id, staff = user
    mode = 1 if staff else 0

    optClient="""
    [Q] main menu
    [r] show repertoire 
    [p] show your reservations
    [c] cancel reservation
    [s] make reservation"""

    optStaff =  optClient + """
    [F] add film
    [S] add seance
    [DF] delete film
    [DS] delete seance
    [U] add user
    [FB] print Film Base
    [R] clear repetoire"""

    options = (optClient, optStaff)
    output = "[OUTPUT SCREEN]"
    opt = options[mode]

    while True:
        mainView(opt,output)
        res = input("Type your option: ")
        if res == 'r':
            output = getRepertoire()
            output = "[No repertoire]" if output is None else output

        elif res ==  "p":
            output = getReservation(user_id)
            output = "[No reservations]" if output is None else output
            
        elif res ==  "c": # delete reservation
            output = getReservation(user_id)
            if output is not None:
                opt_num = output.shape[0]
                while True:
                    opt = """[ Choose from 0 to  %d ]
                    [b] back"""%(opt_num-1)
                    mainView(opt,output)
                    res = input("Type your option: ")
                    try:
                        if res == 'e':
                            exitApp()
                        elif res == 'b':
                            break
                        elif int(res) in range(opt_num):
                            seans_id = output['seans_id'][int(res)]
                            cancelReservation(user_id,seans_id)
                            output =  getReservation(user_id)
                            break
                    except ValueError:
                        print("[Wrong option, Try again]")
                        input()
            else:
                output = "[You have no reservations]"

        elif res == "s": # make reservation 
            output = getRepertoire(NOW,3)
            if output is not None:
                opt_num = output.shape[0]
                while True:
                    opt = "[ Choose from 0 to  %d ]"%(opt_num-1)
                    opt += "\n[b] back"
                    mainView(opt,output)
                    res = input("Type your option: ")
                    try:
                        if res == 'e':
                            exitApp()
                        elif res == 'b':
                            break
                        elif int(res) in range(opt_num):
                            id = output.loc[int(res)]['id']
                            seats_limit = min(10,output.loc[int(res)]['available_seats'])
                            how_many = int(input("How many seats [max %d]: "%(seats_limit)))
                            if how_many not in range(1, seats_limit+1):
                                raise ValueError('[Wrong seats number]')
                            addSeanceToCart(user_id,id,how_many)
                            break
                    except ValueError:
                        print("[Wrong option, Try again]")
                        input()
            else:
                output = "[No repertoire]"

        elif res == "F" and mode: # add film
            accept = False
            while not accept:
                try:
                    print("Fill the following fields: ")
                    title = input("Title: ")
                    dirc = input("Director: ")
                    duration  = input("Time ( format: HH:MM ): ")
                    year = int(input("year of prod.: "))
                    overview = input("short description: ")
                    accept = bool(input("Do you approve changes [yes = 1/ no = 0]? "))
                except ValueError:
                    print("[Wrong Value]")
            
            res = addFilm(title, duration, dirc, year, overview)
            output =  "[Filmes  Added]" if res else "[Cannot add Film]"

        elif res =="S" and mode: # add Seance
            accept = False
            try:
                while not accept:
                    print("Fill the following fields: ")
                    film = input("Title of film: ")
                    date  = input("Date (format:  YYYY-MM-DD HH:MM): ")
                    room = int(input("Which room?: "))
                    accept = input("Do you approve changes [yes = 1/ no = 0]? ")
                    
                    if accept == 'e':
                        exitApp() 
                addSeance(film,date,room)    
                
            except ValueError:
                print('[Wrong Value]')
                input()
            output = getRepertoire()  
        
        elif res == "DF" and mode: # delete film
            output = getFilmBase()
            opt_num = output.shape[0]
            opt = "[Choose from 0 to %d]" %(opt_num-1)
            mainView(opt,output)

            while True:
                res = input("Type number to delete film: ")

        elif res == "R" and mode: # clear repertoire 
            clearRepertoire()
            output ="[Repertoire Cleared]"

        elif res == "FB":
            output = getFilmBase()
            output = "[No Films]" if output is None else output

        elif res == "e":   
            exitApp()
        elif res == "U":
            pass
        elif res == 'Q':
            output = "[OUTPUT SCREEN]"
            opt = options[mode]
        else:
            output = "[Wrong Command!]"
            opt = options[mode]

def signUpUser():
    res = False
    res2 = True

    while (not res) and res2 :
        os.system('CLS')
        print("[[Signning Up]]")
        login = input("Login: ")
        password = input("Password: ")
        res2 = createUser(login, password)
        res = isUser(login,password)
        if not res:
            print("[User %s cannot be added]"%login)
        
    

def loginUser() -> None:
    """
        returns True if 
    """
    cond = False
    res2= False

    while not cond:
        os.system('CLS')
        print("[[Logging in]]")
        login = input("Login: ")
        password = input("Password: ")
        staff = input("Are you staff [y/n]?: ")
        staff = True if staff == 'y' or staff == 'Y' else False
        cond = isUser(login,password,staff)

        if not cond:
            print("[No user: %s, %s]"%(login, password))
            res2 = input("Do you want to Sign Up [y/n]?")
            res2 = True if (res2 == "y" or res2 == " Y") else False
            if res2:
                signUpUser()
            
            exitApp()
        else:
            print("[Logged in]")
            # print(getUserId(login, password),"staff: ",staff)
            serviceLoop(user = (getUserId(login, password), staff))
    
###  other    


### basic tests

def testConnection():
    conn = connect()
    curr  = conn.cursor()
    curr.execute("SELECT freeRooms('2022-06-30 18:00:00','02:00:00');")
    d = curr.fetchall()
    curr.execute("SELECT * FROM freerooms();") 
    curr.close()

def testUsersAddingSignUp():
    print(isUser('superadmin','super'))
    createUser('superadmin','super',True)
    createUser('superadmin','super',True)
    print(isUser('superadmin','super'))
    print(isAdmin('superadmin','super'))
    # check if there's only one superadmin

def testLoginAndSignUp():
    loginUser()

def testReservation():
    loginUser()
    

if __name__ == '__main__':
    testLoginAndSignUp()
    # print(getRepertoire())
