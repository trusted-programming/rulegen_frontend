import streamlit as st
import requests
from streamlit_lottie import st_lottie
from PIL import Image
import os
import pandas as pd

from sidebar import sidebar
from utils import (
    parse_txt,
)

st.set_page_config(page_title="Txl Rule Generation", layout="wide")


st.title('Txl Rule Generation')
st.markdown('This is a workbench for predicting missing TXL rules. You can upload **code before, code after and context rules files** to predict the missing one rule.')

# sidebar()

# ---------------------
st.markdown("## Code before")
def clear_submit():
    st.session_state["submit"] = False
 
uploaded_before_file = st.file_uploader(
    label="You can upload a .txt file here",
    type=["txt"],
    accept_multiple_files=False,
    # help="Scanned documents are not supported yet!",
    on_change=clear_submit,
)

before_doc = None
if uploaded_before_file is not None:
    if uploaded_before_file.name.endswith(".txt"):
        before_text = uploaded_before_file.read().decode("utf-8")
        st.write(before_text)
    else:
        raise ValueError("File type not supported!")

before_input_text = st.text_area("OR you can input the code here", key="before", on_change=clear_submit)
# ---------------------------
st.markdown("## Code after")
    
uploaded_after_file = st.file_uploader(
    "Please upload a **code after** file with .txt extension",
    type=["txt"],
    accept_multiple_files=False,
    # help="Scanned documents are not supported yet!",
    on_change=clear_submit,
)

after_doc = None
if uploaded_after_file is not None:
    if uploaded_after_file.name.endswith(".txt"):
        after_text = uploaded_after_file.read().decode("utf-8")
        st.write(after_text)
    else:
        raise ValueError("File type not supported!")

after_input_text = st.text_area("OR you can input the code here", key="after", on_change=clear_submit)
# ---------------------------
st.markdown("## Context rules")
    
uploaded_context_file = st.file_uploader(
    "Please upload a **context rules** file with .txt extension",
    type=["txt"],
    accept_multiple_files=False,
    # help="Scanned documents are not supported yet!",
    on_change=clear_submit,
)

context_doc = None
if uploaded_context_file is not None:
    if uploaded_context_file.name.endswith(".txt"):
        context_text = uploaded_context_file.read().decode("utf-8")
        st.write(context_text)
    else:
        raise ValueError("File type not supported!")

context_input_text = st.text_area("OR you can input the code here", key="context", on_change=clear_submit)
def local_css(file_name):
    with open(file_name) as f:
        st.markdown(f"<style>{f.read()}</style>", unsafe_allow_html=True)


local_css("style/style.css")

my_form = st.form(key = "form1")
st.selectbox('Please choose the model to predict the missing rule', ['CodeT5', 'CodeBERT', 'StarCoder'], key="model")

submitted = st.button('Predict')
   
# Data Inference
data_inf = {
   'before': before_input_text,
   'after': after_input_text,
   'context': context_input_text
}

data_inf = pd.DataFrame([data_inf])

if submitted:
    st.write('## The predicted missing rule is as below: ')
    missing_rule="nihao"
    st.download_button('download the predicted missing rule', missing_rule)
  