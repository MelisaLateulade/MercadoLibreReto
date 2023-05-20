from flask import Flask, request, jsonify, redirect
import uuid
import redisUtils
import os

app = Flask(__name__)
APIHOST = os.getenv('DNS_LB')

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return "healty", 200

@app.route('/shorturl', methods=['POST']) 
def shorten_url():
    data = request.get_json()  
 
    if data and 'url' in data:
        longurl = data['url']
        shorturl = redisUtils.get_short_url(longurl)
        if shorturl:
            return "short link already exists: " + shorturl, 200
        else:
            shorturl = APIHOST+str(uuid.uuid4())[:8] 
            redisUtils.insert_short_to_long (shorturl, longurl)
            redisUtils.insert_long_to_short (longurl,shorturl)
            return "Data received " + shorturl, 200
    else:
        return "No url in the request", 400
    
@app.route('/shorturl', methods=['GET']) 
def get_short_url():  
    longurl = request.args.get('url') 
    if longurl:
        shorturl = redisUtils.get_short_url(longurl) 
        if shorturl:
            return jsonify({'shorturl': shorturl}), 200
        else:
            return "No url stored", 400
    else:
       return "No url in the request", 400  

@app.route('/shorturl', methods=['DELETE'])
def delete_short_url():
    shorturl = request.args.get('url')
    longurl = redisUtils.get_long_url(shorturl)
    if longurl:
        redisUtils.delete_url(shorturl,longurl)
        return "Sucess", 200
    else:
        return "URL Not Found", 404


@app.route('/longurl', methods=['GET']) 
def get_long_url():  
    shorturl = request.args.get('url') 
    if shorturl:
        longurl = redisUtils.get_long_url(shorturl) 
        if longurl:
            return jsonify({'longurl': longurl}), 200
        else:
            return "No url stored", 400
    else:
       return "No url in the request", 400  
    
@app.route('/<shorturl>')
def redirect_longurl (shorturl):
    longurl = redisUtils.get_long_url(APIHOST+shorturl)
    if longurl:
        return redirect(longurl)
    else:
        return "Short URL not found", 404    

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
