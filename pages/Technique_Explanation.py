import streamlit as st
from PIL import Image

st.markdown("# Technique Explanation ❄️")
st.sidebar.markdown("# Technique Explanation ❄️")

st.write("This demo leverages machine learning models to automatically \
    generate the missing TXL rule, denoted as c. The goal is to ensure \
    that the combined rule set C', formed by integrating the newly predicted TXL \
    rule c with the existing context rule set C, can successfully transform \
        the given **code before** into the desired **code after**. ")

st.markdown("## 1. Dataset Collection")
st.write("We initially gathered triplets comprising of **(code before, code after, TXL rules)**, \
    where the TXL rules are capable of transforming the **code before** into the **code after**. \
    The data was sourced from three different parts as outlined below:")


lst = ['Standard examples from the official website [1];', 
       'C2rust examples from the paper transforming C to Rust [2];',  
       'Rosseta code (317) instances used in inner source C2Rust experiments.']

s = ''

for i in lst:
    s += "- " + i + "\n"

st.markdown(s)

st.markdown("## 2. Dataset Preprocessing")
st.write("Due to the scarcity of TXL rule transformations, \
    the limited number of available TXL transformations poses challenges \
        in effectively applying machine learning techniques. Additionally, \
        identifying the most relevant rule for achieving the desired conversion \
        becomes more difficult. In order to overcome these issues, we have developed \
        a data extraction method that enables the generation of all possible TXL \
        transformations.")

outer_cols = st.columns([1, 1])
with outer_cols[0]:
    image = Image.open('/Users/lichunmiao/SynologyDrive/rulegen_frontend/images/txl_big.jpg')
    st.image(image, caption='Original TXL rules.')
with outer_cols[1]:
    image = Image.open('/Users/lichunmiao/SynologyDrive/rulegen_frontend/images/txl_alg1_1.jpg')
    st.image(image, caption='TXL rules produced by the data extraction method.')
    
st.markdown("We extracted all possible TXL transformations from the original TXL rules.\
 First, we analyzed the rule call graph of the original TXL rules (refer to the left image above).\
 Next, we sliced each path from the main rule to a leaf rule in the call graph to generate a new set of TXL rules (refer to the right image above).\
 Afterwards, we obtained multiple **code after** by applying the newly created TXL rules to **code before**.\
 Finally, for a set of TXL rules, we designated each rule as a hole and retained the remaining rules as **context**, allowing us to construct the training dataset.\
 The dataset comprises quadruples, each consisting of the following elements: **(code before, code after, context rules, hole rules)**. \
    ")


st.markdown("## 3. Model Training")
st.write("We use the preprocessed dataset to train a machine learning model ")

st.markdown("## 4. Performance Evaluation")


st.markdown("## References")
st.write("[1] TXL Resources. (n.d.). Retrieved June 7, 2023, from https://www.txl.ca/txl-resources.html")
st.write("[2] In rust we trust – a transpiler from unsafe C to safer rust, M Ling. et al.")