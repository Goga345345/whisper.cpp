import subprocess
import sys
import os

def process_audio(wav_file, model_name="base.en"):
    """
    Processes an audio file using a specified model and returns the processed string.

    :param wav_file: Path to the WAV file
    :param model_name: Name of the model to use
    :return: Processed string output from the audio processing
    :raises: Exception if an error occurs during processing
    """

    model = f"./models/ggml-{model_name}.bin"

    # Check if the file exists
    if not os.path.exists(model):
        raise FileNotFoundError(f"Model file not found: {model} \n\nDownload a model with this command:\n\n> bash ./models/download-ggml-model.sh {model_name}\n\n")

    if not os.path.exists(wav_file):
        raise FileNotFoundError(f"WAV file not found: {wav_file}")

    binary = None
    if os.path.exists("./build/bin/whisper-cli"):
        binary = "./build/bin/whisper-cli"
    elif os.path.exists("./whisper-cli"):
        binary = "./whisper-cli"
    else:
        binary = "./main"

    cmd = [binary, "-m", model, "-f", wav_file, "-nt"]

    process = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    if process.returncode != 0:
        raise Exception(f"Error processing audio: {process.stderr.strip()}")

    decoded_str = process.stdout.strip()
    processed_str = decoded_str.replace("[BLANK_AUDIO]", "").strip()

    return processed_str

def main():
    if len(sys.argv) >= 2:
        wav_file = sys.argv[1]
        model_name = sys.argv[2] if len(sys.argv) == 3 else "base.en"
        try:
            result = process_audio(wav_file, model_name)
            print(result)
        except Exception as e:
            print(f"Error: {e}")
    else:
        print("Usage: python whisper_processor.py <wav_file> [<model_name>]")

if __name__ == "__main__":
    main()
