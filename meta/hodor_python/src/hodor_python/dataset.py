import requests
import pandas as pd

def download_tab_file(output_path: str):
    url = "https://doi.pangaea.de/10.1594/PANGAEA.980059?format=textfile"
    response = requests.get(url)
    response.raise_for_status()  # Raise an error for bad status codes
    with open(output_path, 'wb') as f:
        f.write(response.content)



def hodor_as_pandas(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    # Find end of header
    for i, line in enumerate(lines):
        if line.startswith('*/') and not line.strip() == '':
            header_idx = i
            break
    # Read the data using pandas, skipping the header block
    df = pd.read_csv(filepath, sep='\t', skiprows=header_idx)
    return df