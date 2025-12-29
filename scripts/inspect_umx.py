
import os
import torch
import openunmix.utils

separator = openunmix.utils.load_separator(
    model_str_or_path="umxhq", 
    niter=1,
    residual=True,
    device="cpu"
)

print(f"Separator type: {type(separator)}")
print(f"Attributes: {dir(separator)}")
if hasattr(separator, 'models'):
    print(f"Models keys: {separator.models.keys()}")
vocals = separator.target_models['vocals']
print(f"Vocals Model: {vocals}")

# Create dummy input equivalent to a spectrogram
# OpenUnmix uses nfft=4096 -> 2049 frequency bins
# Channels=2
# Time=100 frames
frames = 100
freqs = 2049 
dummy_spec = torch.randn(1, 100, 4098) # Wait, OpenUnmix might take (Batch, Time, Channels*Freq)? Or (Batch, Channels, Freq, Time)?
# OpenUnmix (UMX) forward signature: (x) where x is (nb_samples, nb_channels, nb_bins, nb_frames) in older versions
# OR (nb_samples, nb_frames, nb_bins*nb_channels) for LSTM?

# Let's check logic inside OpenUnmix
print("Attempting to infer shape...")
# Usually OpenUnmix takes (Batch, Channels, Freq, Time)
dummy_spec = torch.randn(1, 2, 2049, 100) 
try:
    out = vocals(dummy_spec)
    print(f"Success with (1, 2, 2049, 100). Output: {out.shape}")
except Exception as e:
    print(f"Failed with (1, 2, 2049, 100): {e}")

# Try other shape
dummy_spec_2 = torch.randn(1, 100, 2049*2)
try:
    out = vocals(dummy_spec_2)
    print(f"Success with (1, 100, 4098): {out.shape}")
except Exception as e:
    print(f"Failed with (1, 100, 4098): {e}")

