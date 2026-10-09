#!/usr/bin/env python
import math
import requests

r = requests.get("https://api.frankfurter.dev/v2/rates?base=usd&quotes=cop")
if r.status_code == 200:
    rate1 = r.json()[0]
    print(f'${math.floor(rate1['rate'])}')