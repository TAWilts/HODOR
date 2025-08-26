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

    def _load_dataframe(self) -> pd.DataFrame:
        """
        Loads the hodor .tab file file into a pandas DataFrame.
        The method reads the file specified by `self.filepath`, identifies the end of the header block (marked by a line starting with "*/"),
        and loads the remaining data using pandas. It converts the "Date/time start" and "Date/time end" columns to datetime objects,
        and renames the columns to more readable names.
        Returns:
            pandas.DataFrame: The loaded and processed DataFrame with standardized column names.
        """

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

        # use prettier column names
        df.columns = [
            "SeqID",
            "sequenceStartUnix",
            "sequenceEndUnix",
            "DateTimeStart",
            "DateTimeEnd",
            "anguilla_anguilla",
            "bird_cormorant",
            "bird_unspecified",
            "crab_crustacea",
            "fish_clupeidae",
            "fish_cod",
            "fish_mackerel",
            "fish_mugilidae",
            "fish_oncorhynchus",
            "fish_pipefish",
            "fish_plaice",
            "fish_salmonidae",
            "fish_scad",
            "fish_unspecified",
            "jellyfish_aurelia",
            "jellyfish_ctenophora",
            "jellyfish_cyanea",
            "jellyfish_unspecified",
        ]
        return df
