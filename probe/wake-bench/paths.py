"""The data folder of the bench: models, voices, LibriSpeech, frames and results.
Set WAKE_DATA to change it. The folder is not in the repository."""
import os

DATA = os.environ.get("WAKE_DATA", os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
