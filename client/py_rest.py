#!/bin/python

import requests
import json
from getpass import getpass

response = requests.get('https://al2s.net.internet2.edu//oess/services-kerb/data.cgi',auth=('lzhang9', getpass()))
print(response.json())
