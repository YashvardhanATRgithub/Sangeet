
import torch
import openunmix
import coremltools as ct
import shutil
import os

def convert_openunmix():
    print("Loading OpenUnmix (umxhq)...")
    # Load the full waveform-to-waveform separator
    # This automatically handles STFT/ISTFT internally
    # OpenUnmix 1.2+ uses 'model' or 'target'
    # 'umxhq' loads a dictionary of models (vocals, drums, etc.)
    # We want a Separator that wraps them.
    # Actually, umx.utils.load_separator constructs it.
    
    # API based on inspection:
    separator = openunmix.utils.load_separator(
        model_str_or_path="umxhq", 
        niter=1,
        residual=True,
        device="cpu"
    )
    separator.eval()
    
    print("Tracing model...")
    # OpenUnmix takes Short inputs better for tracing?
    # Let's try 3 seconds to keep graph size manageable.
    # Input shape: (Batch, Channels, Time) => (1, 2, 44100*3)
    samples = 44100 * 3  
    example_input = torch.randn(1, 2, samples)
    
    # We trace the WHOLE separator (Waveform -> Waveform)
    # check_trace=False because Wiener filtering has dynamic loops that confuse the validator
    traced_model = torch.jit.trace(separator, example_input, check_trace=False)
    
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
    
    print("\n✅ SUCCESS!")

if __name__ == "__main__":
    convert_openunmix()
