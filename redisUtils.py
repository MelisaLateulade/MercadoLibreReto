import redis
import os

DATABASE_HOST = os.getenv('DATABASE_HOST')        

def insert_short_to_long (shorturl, longurl):
    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=0)  
    r.set (shorturl,longurl) 

def get_long_url(shorturl):
    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=0) 
    longurl = r.get (shorturl) 
    if longurl:
        return longurl.decode('utf-8')
    else:
        return longurl

def insert_long_to_short (longurl, shorturl):
    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=1)  
    r.set (longurl, shorturl) 
    
def get_short_url(longurl):
    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=1)  
    shorturl = r.get (longurl) 
    if shorturl:
        return shorturl.decode('utf-8')
    else:
        return shorturl

def delete_url(shorurl,longurl):
    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=0)  
    r.delete(shorurl)

    r = redis.Redis(
    host=DATABASE_HOST,
    port=6379,
    db=1)  
    r.delete(longurl)
      