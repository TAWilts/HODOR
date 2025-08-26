import requests
import pandas as pd
from pathlib import Path
from enum import Enum


class Species(str, Enum):
    """Enum for species in the HODOR dataset. Use it e.g. to filter data by species."""
    ANGUILLA_ANGUILLA = "anguilla_anguilla"
    BIRD_CORMORANT = "bird_cormorant"
    BIRD_UNSPECIFIED = "bird_unspecified"
    CRAB_CRUSTACEA = "crab_crustacea"
    FISH_CLUPEIDAE = "fish_clupeidae"
    FISH_COD = "fish_cod"
    FISH_MACKEREL = "fish_mackerel"
    FISH_MUGILIDAE = "fish_mugilidae"
    FISH_ONCORHYNCHUS = "fish_oncorhynchus"
    FISH_PIPEFISH = "fish_pipefish"
    FISH_PLAICE = "fish_plaice"
    FISH_SALMONIDAE = "fish_salmonidae"
    FISH_SCAD = "fish_scad"
    FISH_UNSPECIFIED = "fish_unspecified"
    JELLYFISH_AURELIA = "jellyfish_aurelia"
    JELLYFISH_CTENOPHORA = "jellyfish_ctenophora"
    JELLYFISH_CYANEA = "jellyfish_cyanea"
    JELLYFISH_UNSPECIFIED = "jellyfish_unspecified"

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
            "DateTimeEnd" ] + [s.value for s in Species]

        # new column which holds the duration of each sequence
        df.insert(5, "sequence_length", df["DateTimeEnd"] - df["DateTimeStart"])

        return df
