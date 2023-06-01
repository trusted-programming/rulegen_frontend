import os
import json
from typing import Dict, Any
import requests

from PIL import Image
import base64
from pathlib import Path


# from guesslang import Guess


# guessor = Guess()

def img_to_bytes(img_path):
    img_bytes = Path(img_path).read_bytes()
    encoded = base64.b64encode(img_bytes).decode()
    return encoded
def img_to_html(img_path):
    img_html = "<img src='data:image/png;base64,{}' class='img-fluid'>".format(
      img_to_bytes(img_path)
    )
    return img_html

def request_api(url: str, data: Dict[str, Any]):
    # _input: str, 
    # task: str, 
    # source_lgs: str=None,
    # target_lgs: str=None
    
    """
    Post request to API
    
    Args:
        _input (str): input data
        task (str): task
        url (str): api
        source_lgs (str): Source languages
        target_lgs (str): Target languages
    
    Return:
        respone (json)
    """
    # data = {
    #     "input": _input,
    #     "task": task,
    #     "source_lgs": source_lgs, 
    #     "target_lgs": target_lgs,
    # }
    
    headers = {
        'Content-type': 'application/json', 
        'Accept': 'text/plain'
    }
    response = requests.post(url, data=json.dumps(data), headers=headers)
    return response


def load_image_from_local(image_path, image_resize=None):
    image = Image.open(image_path)

    if isinstance(image_resize, tuple):
        image = image.resize(image_resize)
    return image


def detect_lang(url, input_):
    # name = guessor.language_name(input_)
    responde = request_api(url, {
        'input': input_,
        'task': 'language_detection',
        'source_lgs': None,
        'target_lgs': None
    })
    name = json.loads(responde.text)['output']
    return name