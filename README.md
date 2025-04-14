# 🐟 HODOR: Hydroacoustic and Optical Dataset for Oceanic Research
### High-Quality Optical and Sonar Dataset for Research

Welcome to the official repository of the **HODOR dataset**, a unique long-term multimodal underwater dataset combining synchronized forward-looking sonar and stereo camera data, collected in the Baltic Sea via the autonomous UFO platform. HODOR supports research in object detection, tracking, and sensor fusion in challenging underwater environments.
## 📄 Cite Us

If you use HODOR in your research, please cite:
```bibtex
@ARTICLE{HODOR2025,
  author={Wilts, Thomas and Boeer, Gordon and Winkler, Julian and Others},
  journal={IEEE Data Descriptions}, 
  title={HODOR: Hydroacoustic and Optical Dataset for Oceanic Research}, 
  year={2025},
  volume={},
  number={},
  pages={},
  keywords={},
  doi={}}
}
```
## 📦 What's Inside
![Snapshot of sequence 2895](https://github.com/TAWilts/HODOR/blob/main/sequence2.gif)
> Snapshot of sequence 2895
* 🔹 Synchronized imaging sonar and stereo camera data
* 🔹 Over 400 hours of continuous sequences per sensor
* 🔹 Associated abiotic measurements (e.g., CTD, ADCP, fluorometer) 
* 🔹 Ground-truth tracking annotations (coming soon)

The dataset is available at PANGAEA:

Read the paper:

The associated abiotic measurements:


## 🚀 HOW TO:
Download this repo and place it inside the dataset as shown:

![](https://github.com/TAWilts/HODOR/blob/main/folderStructureMarkdown.png)
> Required folder arrangement. Place this repo inside meta.

## Explore and interact with the dataset using our starter tools:
### 🐍 Python

* hashCheck.py: Test for integrity of the dataset

### 🧠 MATLAB

* visualizeSequence.m: Display all sensor data at the same time (see example-gif above)

* analyzeCompleteSet: Runs through all dataset video files and performs statistical measurements

## 💬 Join the Discussion

We welcome your feedback, questions, and contributions!

* 👉 Use the Issues tab for bug reports and feature requests

* 👉 Start a thread in Discussions to share research ideas or get support

* 👉 Fork the repo and send us a pull request to contribute new tools, improvements, or annotations


Let’s build the future of underwater perception—together. 🌊🤿
