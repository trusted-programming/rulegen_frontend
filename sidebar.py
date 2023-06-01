import streamlit as st

def sidebar():
    with st.sidebar:
        BEFORE = st.text_input('Code Before:')
        AFTER = st.text_input('Code After')
        CONTEXT = st.text_input('Context')