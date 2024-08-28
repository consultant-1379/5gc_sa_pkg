#!/lab/pccc_utils/scripts/csdp_python3_venv/bin/python

import sys
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium import webdriver
from selenium.webdriver.common.proxy import Proxy, ProxyType
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.firefox.options import Options
import time
import datetime
import os
import configparser


# read configuration values from the config.ini file
config = configparser.ConfigParser()
config.read('config.ini')
url = config.get('config', 'url')
username = config.get('config', 'username')
password = config.get('config', 'password')
start_time_string = config.get('config', 'start_time')
end_time_string = config.get('config', 'end_time')

# create a FirefoxOptions object to configure the browser
options = Options()
options.headless = True

def login(drive, username, passwd):
    input = drive.find_element(By.NAME, "user")
    input.send_keys(username)

    input = drive.find_element(By.NAME, "password")
    input.send_keys(passwd)

    input.send_keys(Keys.ENTER)
    drive.implicitly_wait(300)

if __name__ == "__main__":
   # prox = Proxy()
   # prox.proxy_type = ProxyType.MANUAL
   # prox.socksProxy = "localhost:9888"
   # capabilities = webdriver.DesiredCapabilities.CHROME
   # prox.add_to_capabilities(capabilities)
   # capabilities['proxy']['socksVersion'] = 5

   # driver = webdriver.Firefox(desired_capabilities=capabilities)
    driver = webdriver.Firefox(options=options)
    driver.maximize_window()
    driver.get(url)
    login(driver, username, password)

    # convert time string to timestamp
    start_time_stamp = int(time.mktime(time.strptime(start_time_string, '%m/%d/%Y %H:%M:%S'))* 1000)
    end_time_stamp = int(time.mktime(time.strptime(end_time_string, '%m/%d/%Y %H:%M:%S'))* 1000)

    file = open('panelid.txt')

    for line in file.readlines():
        panelid = line.strip()
        url_panel = url+"?from="+f'{start_time_stamp}'+"&to="+f'{end_time_stamp}'+"&viewPanel="+panelid
        print(url_panel)
        time.sleep(10)
        driver.get(url_panel)

        time.sleep(10)
        ele_panel = driver.find_element(By.CLASS_NAME, "panel-container")
        driver.implicitly_wait(300)
        title = driver.find_element(By.CLASS_NAME, "panel-title").get_attribute("textContent")
        WebDriverWait(driver, 10).until(EC.visibility_of(ele_panel))
        ele_panel.screenshot(title + '.png')
    driver.close()
