import time
import telnetlib
import geocoder
import asyncio
from winsdk.windows.devices.geolocation import Geolocator

async def get_precise_coords():
    locator = Geolocator()
    # Request high-accuracy Wi-Fi/GPS triangulation
    pos = await locator.get_geoposition_async()
    
    lat = pos.coordinate.point.position.latitude
    lng = pos.coordinate.point.position.longitude
    
    return lat, lng

# Setup connection variables
PORT = 5554  # Check your emulator window title for the correct port (usually 5554)
AUTH_TOKEN = "KDeuaGYjTja8WVAT"  # Paste the token from Step 1

print("Connecting to Android Emulator...")
try:
    # Establish connection to the emulator console
    tn = telnetlib.Telnet("localhost", PORT)
    tn.read_until(b"OK", timeout=2)
    
    # Authenticate the console session
    tn.write(f"auth {AUTH_TOKEN}\n".encode('ascii'))
    tn.read_until(b"OK", timeout=2)
    print("Successfully connected to emulator!")

    while True:
        try:
            lat, lng = asyncio.run(get_precise_coords())
            command = f"geo fix {lng} {lat}\n"
            tn.write(command.encode('ascii'))
            print(f"Precise GPS Synced: Lat {lat}, Lng {lng}")
        except Exception as e:
            print(f"Make sure 'Location Services' is enabled in Windows Settings. Error: {e}")
        time.sleep(5)

except Exception as e:
    print(f"Error: {e}")
