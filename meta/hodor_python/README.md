# Example Notebooks

This repository includes example Jupyter notebooks to help you get started with the HODOR dataset and its Python interface. Below are summaries of the available notebooks and what you can learn from them:

## 1. `download_data.ipynb`

**Purpose:**
- Demonstrates how to download data from the HODOR dataset using the provided Python API.
- Shows how to create a dataset instance, download specific sequences, and manage local storage efficiently (files are not re-downloaded if they already exist).
- Explains the hierarchical storage system of Pangaea and how the downloader handles files that need to be retrieved from tape storage.
- Provides strategies for targeted downloading, such as identifying sequences with high activity for a particular species (e.g., cod) and downloading only those sequences.

**Key Features:**
- Safe, repeatable downloads (skips files already present)
- Filtering and identifying interesting sequences based on species activity
- Downloading only the data you need for your research

## 2. `usage_examples.ipynb`

**Purpose:**
- Provides practical examples for loading and analyzing HODOR metadata and animal activity counts using pandas DataFrames.
- Demonstrates common data analysis tasks, such as filtering, grouping, sorting, and plotting species counts.
- Shows how to calculate new columns, aggregate data, and visualize results with pandas plotting functions.

**Key Features:**
- Loading and parsing HODOR tabular metadata
- Filtering rows by species activity
- Grouping and aggregating counts by date or other fields
- Sorting and ranking sequences by length or species count
- Creating new columns (e.g., sequence duration)
- Summarizing and visualizing data with plots and pivot tables

---

For more details, open the notebooks in the `notebooks/` directory and follow the step-by-step code and explanations. These examples are a great starting point for your own analyses with the HODOR dataset.
