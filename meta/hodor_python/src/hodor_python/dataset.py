import pandas as pd
from pathlib import Path
from enum import Enum
from pangaeapy import PanDataSet


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
    PANGAEA_DATASET_ID = 980059

    def __init__(self, dataset_folder: str):
        self.dataset_folder = Path(dataset_folder)

        # internally used pangaeapy dataset
        self._ds = PanDataSet(self.PANGAEA_DATASET_ID, cachedir=dataset_folder)

        self.df: pd.DataFrame = self._load_dataframe()

    def _load_dataframe(self) -> pd.DataFrame:
        """
        Converts the pangaeapy dataframe into a more user-friendly DataFrame.
        It converts the "Date/time start" and "Date/time end" columns to datetime objects,
        and renames the columns to more readable names.
        Returns:
            pandas.DataFrame: The loaded and processed DataFrame with standardized column names.
        """

        # remove unused columns
        df = self._ds.data.drop(columns=["Event", "Latitude", "Longitude", "Date/Time"])

        # Convert datetime columns
        df["Date/time start"] = pd.to_datetime(df["Date/time start"])
        df["Date/time end"] = pd.to_datetime(df["Date/time end"])

        # use prettier column names
        df.columns = [
            "SeqID",
            "sequenceStartUnix",
            "sequenceEndUnix",
            "DateTimeStart",
            "DateTimeEnd",
        ] + [s.value for s in Species]

        # new column which holds the duration of each sequence
        df.insert(5, "sequence_length", df["DateTimeEnd"] - df["DateTimeStart"])

        return df
