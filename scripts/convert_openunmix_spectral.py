
import torch
import openunmix.utils
import coremltools as ct
import shutil
import os

def convert_spectral():
    print("Loading OpenUnmix Vocals Model...")
    # Load the full separator to get the vocal sub-model
    separator = openunmix.utils.load_separator(
        model_str_or_path="umxhq", 
        niter=1,
        residual=True,
        device="cpu"
    )
    vocals_model = separator.target_models['vocals']
    vocals_model.eval()
    
    # Input params based on umxhq details
    nb_channels = 2
    nb_bins = 2049 # nfft=4096
    
    # Trace with dummy input
    # Time frames = 100 (approx 2s at hop=1024)
    dummy_frames = 100
    dummy_input = torch.randn(1, nb_channels, nb_bins, dummy_frames)
    
    print(f"Tracing with input: {dummy_input.shape}...")
    traced_model = torch.jit.trace(vocals_model, dummy_input)
    
    print("Converting to Core ML...")
    # Define flexible input shape for Time dimension
    # (1, 2, 2049, RangeDim)
    # RangeDim allows variable number of frames
    time_dim = ct.RangeDim(lower_bound=10, upper_bound=5000, default=100)
    
    _input = ct.TensorType(name="magnitude_spectrogram", shape=(1, 2, 2049, time_dim))
    
    mlmodel = ct.convert(
        traced_model,
        inputs=[_input],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS13
    )
    
    mlmodel.author = "Sangeet AI"
    mlmodel.short_description = "OpenUnmix Vocals (Spectral)"
    
    output_path = "OpenUnmixSpectrogram.mlpackage"
    print(f"Saving to {output_path}...")
    mlmodel.save(output_path)
    
    print("Zipping...")
    shutil.make_archive("OpenUnmixSpectrogram", 'zip', output_path)
    
    print("\n✅ SUCCESS!")

if __name__ == "__main__":
    convert_spectral()
