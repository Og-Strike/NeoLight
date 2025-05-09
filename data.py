import time
from datetime import datetime
import requests
import pytz
from pymongo import MongoClient

# MongoDB Config
MONGO_URI = "mongodb://localhost:27017/"
client = MongoClient(MONGO_URI)
db = client['neolight']
collection = db['data']

# Weather API Config
API_KEY = "d046ee4e275e139630535c7d2a218b93"
CITY = "New Delhi"
COUNTRY = "IN"

# Fetch weather data
def get_weather():
    url = f"http://api.openweathermap.org/data/2.5/weather?q={CITY},{COUNTRY}&appid={API_KEY}&units=metric"
    response = requests.get(url).json()

    if response.get('cod') != 200:
        print("Error fetching weather data:", response)
        return None

    sunrise_time = datetime.fromtimestamp(response['sys']['sunrise']).strftime('%H:%M:%S')
    sunset_time = datetime.fromtimestamp(response['sys']['sunset']).strftime('%H:%M:%S')

    return {
        'weather': response['weather'][0]['main'].lower(),
        'sunrise': sunrise_time,
        'sunset': sunset_time
    }

# Update MongoDB every 10 minutes
def update_loop():
    while True:
        try:
            now = datetime.now(pytz.timezone('Asia/Kolkata'))
            current_time = now.strftime("%H:%M:%S")
            current_date = now.strftime("%d-%m-%Y")

            weather_data = get_weather()

            if weather_data:
                document = {
                    'name': 'neo',
                    'date': current_date,
                    'time': current_time,
                    'weather': weather_data['weather'],
                    'sunrise': weather_data['sunrise'],
                    'sunset': weather_data['sunset']
                }

                collection.update_one({'name': 'neo'}, {'$set': document}, upsert=True)
                # print(collection.find_one())
                print(f"[{current_time}] MongoDB updated for 'neo'")
            else:
                print("Skipping update due to weather fetch error.")

        except Exception as e:
            print("Error:", str(e))

        time.sleep(60)  # Wait 10 minutes

# Start the loop
update_loop()
