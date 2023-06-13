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
# Define your samples
sample_keys = ['Sample 1', 'Sample 2', 'Sample 3', 'Sample 4', 'Sample 5']
samples = {}

# Loop through the sample keys to populate the dictionary
for key in sample_keys:
    before_path = f'samples/{key.lower().replace(" ", "_")}/before.txt'
    after_path = f'samples/{key.lower().replace(" ", "_")}/after.txt'
    context_path = f'samples/{key.lower().replace(" ", "_")}/context.txt'

    # Check that the files exist before trying to read them
    if os.path.exists(before_path) and os.path.exists(after_path) and os.path.exists(context_path):
        with open(before_path, 'r') as bf, open(after_path, 'r') as af, open(context_path, 'r') as cf:
            before = bf.read()
            after = af.read()
            context = cf.read()

        samples[key] = {
            'before': before,
            'after': after,
            'context': context,
        }

selected_sample_key = st.selectbox('Or choose a predefined sample', sample_keys)

# Fetch the selected sample
selected_sample = samples.get(selected_sample_key)


existing_contexts = ['Array', 'Atoi', 'Const2mut', 'Errno Location', 'Fn', 'Formalize Code', 'Main', 'Null', 'Stdio', 'Time', 'Unsafe', 'Var Type No Bounds']
contexts = {}

# Loop through the sample keys to populate the dictionary
for context in existing_contexts:
    context_path = f'context/{context.lower().replace(" ", "_")}.txl'  # Replace 'key' with 'context' and fix file extension
  
    # Check that the files exist before trying to read them
    if os.path.exists(context_path):
        with open(context_path, 'r') as context_f:  # Add colon (:)
            context_data = context_f.read()
            
        # Populate dictionary
        contexts[context] = context_data

# Add dropdown for contexts in Streamlit
selected_context = st.selectbox('Choose an existing context', list(contexts.keys()), key="context_file")

# Fetch the selected context
selected_context_data = contexts.get(selected_context)

if selected_context_data:
    context_input_text_default = selected_context_data


# If a sample was selected, populate the text inputs with its data
if selected_sample:
    before_input_text_default = selected_sample['before']
    after_input_text_default = selected_sample['after']
    context_input_text_default = selected_sample['context']
else:
    before_input_text_default = ""
    after_input_text_default = ""
    context_input_text_default = ""

with col1:
    st.markdown("## Code before")
    uploaded_before_file = st.file_uploader(
        label="Upload a **code before** file with .txt extension",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    before_input_text = st.text_area("OR input the code here", value=before_input_text_default, key="before", height=300)

with col2:
    st.markdown("## Code after")
    uploaded_after_file = st.file_uploader(
        "Upload a **code after** file with .txt extension",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    after_input_text = st.text_area("OR input the code here", value=after_input_text_default, key="after", height=300)

with col3:
    st.markdown("## Context rules")
    uploaded_context_file = st.file_uploader(
        "Upload a **context rules** file with .txt extension",
        type=["txt"],
        accept_multiple_files=False,
        help="Scanned documents are not supported yet!"
    )
    context_input_text = st.text_area("OR input the code here", value=context_input_text_default, key="context", height=300)


# Model selection
models = ['CodeT5', 'CodeGen', 'StarCoder']
selected_model = st.selectbox('Choose the model to predict the missing rule', models, key="model")

# Additional parameters
temperature = st.slider('Temperature', min_value=0.0, max_value=1.0, value=0.95, step=0.01)
max_length = st.slider('Max Length', min_value=0, max_value=1024, value=512, step=1)

# Initialize session state
if 'predict_clicked' not in st.session_state:
    st.session_state['predict_clicked'] = False

# Predict button
if st.button('Predict'):
    st.session_state['predict_clicked'] = True
    # Data Inference
    data_inf = {
        'before': before_input_text,
        'after': after_input_text,
        'context': context_input_text
    }
    # POST request to Flask API
    url = 'http://localhost:5000/predict'  # Replace with your Flask API URL
    with st.spinner('Predicting...'):
        response = requests.post(url, json=data_inf)

    if response.status_code == 200:
        missing_rule = response.json()['missing_rule']
        st.write('## The predicted missing rule is as below: ')
        st.session_state['missing_rule'] = missing_rule  # Store the missing rule in the session state
    else:
        st.error('Failed to predict. Please check your inputs and try again.')

# Display the predicted missing rule, if it exists in the session state
if 'missing_rule' in st.session_state:
    st.code(st.session_state['missing_rule'], language='python')  # Display missing_rule as a code block
    st.download_button('Download the predicted missing rule', st.session_state['missing_rule'])

if st.session_state['predict_clicked']:
    # Execute Rule button
    if st.button('Execute Rule'):
        # POST request to Flask API to execute the rule
        url_execute = 'http://localhost:5000/execute'  # Replace with your Flask API URL for executing the rule

        combined_rule = context_input_text + '\n' + st.session_state['missing_rule']

        data_execute = {
            'program': before_input_text,  # assuming 'before' code is the program to be transformed
            'txl': combined_rule  # use the predicted missing rule as TXL script
        }
        with st.spinner('Executing...'):
            response_execute = requests.post(url_execute, json=data_execute)
      
        if response_execute.status_code == 200:
            execution_result = response_execute.json()['transformed_program']
            st.session_state['execution_result'] = execution_result
            st.text_area('Execution Result:', value=st.session_state['execution_result'], height=200, key='execution_result')
        else:
            st.error('Failed to execute the rule.')

if 'execution_result' in st.session_state:
    st.text_area('Execution Result:', value=st.session_state['execution_result'], height=200, key='execution_result')
