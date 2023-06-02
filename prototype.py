import streamlit as st
import requests
from streamlit_lottie import st_lottie
from PIL import Image
import os
import pandas as pd

from utils import parse_txt

st.set_page_config(page_title="Txl Rule Generation", layout="wide")

# Custom Styling
def local_css(file_name):
    with open(file_name) as f:
        st.markdown(f"<style>{f.read()}</style>", unsafe_allow_html=True)

local_css("style/style.css")

# Title
st.title('Txl Rule Generation')
st.markdown('This is a workbench for predicting missing TXL rules. Upload **code before, code after and context rules files** to predict the missing rule.')

# UI Layout
col1, col2, col3 = st.columns(3)
samples = ['Sample 1', 'Sample 2', 'Sample 3']  # Replace these with actual sample names
selected_sample = st.selectbox('Or choose a predefined sample', samples)
with col1:
    st.markdown("## Code before")
    uploaded_before_file = st.file_uploader(
        label="Upload a .txt file here",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    before_input_text = st.text_area("OR input the code here", key="before")

with col2:
    st.markdown("## Code after")
    uploaded_after_file = st.file_uploader(
        "Upload a **code after** file with .txt extension",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    after_input_text = st.text_area("OR input the code here", key="after")

with col3:
    st.markdown("## Context rules")
    uploaded_context_file = st.file_uploader(
        "Upload a **context rules** file with .txt extension",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    context_input_text = st.text_area("OR input the code here", key="context")

# Model selection
models = ['CodeT5', 'CodeGen', 'StarCoder']
selected_model = st.selectbox('Choose the model to predict the missing rule', models, key="model")

# Additional parameters
temperature = st.slider('Temperature', min_value=0.0, max_value=1.0, value=0.5, step=0.01)
max_length = st.slider('Max Length', min_value=0, max_value=1024, value=512, step=1)

# Predict button
if st.button('Predict'):
    # Data Inference
    data_inf = {
       'before': before_input_text,
       'after': after_input_text,
       'context': context_input_text
    }
    data_inf = pd.DataFrame([data_inf])
    st.write('## The predicted missing rule is as below: ')
    missing_rule="nihao"
    st.download_button('Download the predicted missing rule', missing_rule)
