import sys
import requests
import oauth2 as oauth
import urllib.parse



# TWITTER API KEYS #
CONSUMER_KEY=""
CONSUMER_SECRET=""
ACCESS_TOKEN=""
ACCESS_TOKEN_SECRET=""



# Recoge los argumentos que llegan
method = sys.argv[1]
url = sys.argv[2]
media = ""

if len(sys.argv) == 4:
    media = sys.argv[3]

params = {}
files = []

# Si se le pasa archivos multimedia los abre para despues adjuntarlos a la petición
if media != "":
    files.append(("media", open(media, 'rb')))

# Recoge los parametros de la petición, los cuales llegan por la entrada estándar
for line in sys.stdin:
    line = line.strip()
    key = line.split(" ")[0]
    value = line[len(key) + 1:]
    if key != "" and value != "":
        params[key] = value

# Codifica los parametros para la url
url += "?" + urllib.parse.urlencode(params)

# Se hace la petición
consumer = oauth.Consumer(key=CONSUMER_KEY, secret=CONSUMER_SECRET)
access_token = oauth.Token(key=ACCESS_TOKEN, secret=ACCESS_TOKEN_SECRET)
client = oauth.Client(consumer, access_token)

req = oauth.Request.from_consumer_and_token(
    consumer=consumer,
    token=access_token,
    http_method=method,
    http_url=url,
)

req.sign_request(oauth.SignatureMethod_HMAC_SHA1(), consumer, access_token)

headers = req.to_header()

response = requests.request(method, url, headers=headers, files=files)

# La respuesta se saca por la salida estándar
print(response.content.decode())
