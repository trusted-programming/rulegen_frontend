import re
from io import BytesIO
import streamlit as st
from typing import Any, Dict, List
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.docstore.document import Document


@st.cache_data()
def parse_txt(file: BytesIO) -> str:
    text = file.read().decode("utf-8")
    # Remove multiple newlines
    text = re.sub(r"\n\s*\n", "\n\n", text)
    return text

# @st.cache(allow_output_mutation=True)
# def text_to_docs(text: str | List[str]) -> List[Document]:
#     """Converts a string or list of strings to a list of Documents
#     with metadata."""
#     if isinstance(text, str):
#         # Take a single string as one page
#         text = [text]
#     page_docs = [Document(page_content=page) for page in text]

#     # Add page numbers as metadata
#     for i, doc in enumerate(page_docs):
#         doc.metadata["page"] = i + 1

#     # Split pages into chunks
#     doc_chunks = []

#     for doc in page_docs:
#         text_splitter = RecursiveCharacterTextSplitter(
#             chunk_size=800,
#             separators=["\n\n", "\n", ".", "!", "?", ",", " ", ""],
#             chunk_overlap=0,
#         )
#         chunks = text_splitter.split_text(doc.page_content)
#         for i, chunk in enumerate(chunks):
#             doc = Document(
#                 page_content=chunk, metadata={"page": doc.metadata["page"], "chunk": i}
#             )
#             # Add sources a metadata
#             doc.metadata["source"] = f"{doc.metadata['page']}-{doc.metadata['chunk']}"
#             doc_chunks.append(doc)
#     return doc_chunks