
# -----------------------------------------------------------------------------
# Instructions:
# 1. Copy ALL text below.
# 2. Paste into a Google Colab cell.
# 3. Run the cell.
# -----------------------------------------------------------------------------

script = """
set -x # Trace mode: Print every command before running it
set -e # Exit immediately on error

echo "🚀 Setting up isolated environment..."
# Check python version
python3 --version

# Create venv
python3 -m venv venv
source venv/bin/activate

echo "📦 Installing clean dependencies..."
# Upgrade pip inside venv just in case
pip install --upgrade pip

# Install numpy first
pip install "numpy<2"

# Install CPU Torch
pip install torch==2.4.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cpu

# Install others
pip install demucs coremltools

echo "✅ Environment Ready."

# Create the python script to run inside venv
cat <<EOF > run_conversion.py
import torch
import torch.nn as nn
from demucs.pretrained import get_model
from demucs.apply import apply_model
import coremltools as ct
import shutil
import numpy
import sys

print(f'Numpy Version inside venv: {numpy.__version__}')
if numpy.__version__.startswith('2'):
    print('❌ Error: Numpy 2.x still present!')
    sys.exit(1)

class DemucsWrapper(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
        self.model.eval()
        
    def forward(self, x):
        return apply_model(self.model, x, shifts=0, split=True, overlap=0.25, progress=False)

print('Downloading Demucs...')
bag_model = get_model('htdemucs')

if hasattr(bag_model, 'models'):
    model = bag_model.models[0]
else:
    model = bag_model

model.eval()

print('Tracing...')
samples = 343980
example_input = torch.randn(1, 2, samples)
traced_model = torch.jit.trace(model, example_input)

print('Converting...')
_input = ct.TensorType(name="audio", shape=(1, 2, samples))
mlmodel = ct.convert(
    traced_model,
    inputs=[_input],
    convert_to='mlprogram',
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.macOS13
)

output_path = 'Demucs.mlpackage'
mlmodel.save(output_path)
shutil.make_archive('Demucs', 'zip', output_path)
print('✅ Done! Output at Demucs.zip')
EOF

echo "🏃 Running conversion script..."
python run_conversion.py
"""

import subprocess

# Write script to disk
with open("runner.sh", "w") as f:
    f.write(script)

print("Starting isolated shell execution...")
print("----------------------------------------------------------------")
# Run using subprocess to ensure we see the output
try:
    result = subprocess.run(["bash", "runner.sh"], check=True, text=True, capture_output=False)
except subprocess.CalledProcessError as e:
    print(f"\n❌ Script failed with code {e.returncode}")
