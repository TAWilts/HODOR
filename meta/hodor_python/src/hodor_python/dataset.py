import requests
import pandas as pd
from pathlib import Path


class HODOR_Dataset:
    def __init__(self, filepath: str):
        self.filepath = Path(filepath)
        if not self.filepath.exists():
            self.download_tab_file(self.filepath)

        self.df = self._load_dataframe()
        self._url = "https://doi.pangaea.de/10.1594/PANGAEA.980059?format=textfile"

    def download_tab_file(self, output_path: str):
        response = requests.get(self._url)
        response.raise_for_status()
        with open(output_path, "wb") as f:
            f.write(response.content)

    def _load_dataframe(self):
        with open(self.filepath, "r") as f:
            lines = f.readlines()
        # Find end of header
        for i, line in enumerate(lines):
            if line.startswith("*/") and not line.strip() == "":
                header_idx = i
                break
        # Read the data using pandas, skipping the header block
        df = pd.read_csv(self.filepath, sep="\t", header=1, skiprows=header_idx)
        df["Date/time start"] = pd.to_datetime(df["Date/time start"])
        df["Date/time end"] = pd.to_datetime(df["Date/time end"])
        return df
