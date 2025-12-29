
# -----------------------------------------------------------------------------
# Instructions:
# 1. Factory Reset Runtime in Colab.
# 2. Copy ALL text below.
# 3. Paste into a Colab cell and Run.
# -----------------------------------------------------------------------------

import subprocess
import sys

print("⏳ INSTALLING OPENUNMIX...")
# Install OpenUnmix and deps
subprocess.check_call([sys.executable, "-m", "pip", "install", "openunmix", "torch", "torchaudio", "coremltools", "numpy<2"])

import torch
import openunmix
import coremltools as ct
import shutil

def convert_openunmix():
    print("Loading OpenUnmix (umxhq)...")
    # Load the full waveform-to-waveform separator
    # This automatically handles STFT/ISTFT internally
    separator = openunmix.utils.load_separator(
        model_str="umxhq", 
        niter=1,              # 1 iteration of Wiener filter for speed/compatibility
        residual=True, 
        device="cpu"
    )
    separator.eval()
    
    print("Tracing model...")
    # OpenUnmix takes Short inputs better for tracing?
    # Let's try 10 seconds.
    # Input shape: (Batch, Channels, Time) => (1, 2, 44100*10)
    samples = 44100 * 10 
    example_input = torch.randn(1, 2, samples)
    
    # We trace the WHOLE separator (Waveform -> Waveform)
    # This requires STFT support in Core ML (Supported in iOS 14 / macOS 11+)
    traced_model = torch.jit.trace(separator, example_input)
    
    print("Converting to Core ML...")
    _input = ct.TensorType(name="audio", shape=(1, 2, samples))
    
    # OpenUnmix output is dictionary-like in Python but Tuple in Traced Script
    # The output of Separator forward is usually a Tensor of shape (Batch, Targets, Channels, Time)
    
    mlmodel = ct.convert(
        traced_model,
        inputs=[_input],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS13
    )
    
    mlmodel.author = "Sangeet AI"
    mlmodel.short_description = "OpenUnmix (UMXHQ)"
    
    output_path = "OpenUnmix.mlpackage"
    print(f"Saving to {output_path}...")
    mlmodel.save(output_path)
    
    print("Zipping...")
    shutil.make_archive("OpenUnmix", 'zip', output_path)
    
    print("\n✅ SUCCESS!")
    print("Download 'OpenUnmix.zip' from files.")

if __name__ == "__main__":
    convert_openunmix()
